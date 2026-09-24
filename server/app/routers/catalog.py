from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import catalog, charts_sync, explore, fulfill, identify
from ..db import get_db
from ..deps import get_current_user
from ..http import client as http_client
from ..models import DownloadRequest, User
from ..services import navidrome_for

router = APIRouter(tags=["catalog"])


@router.get("/catalog/search")
async def catalog_search(
    q: str = Query(..., min_length=1),
    limit: int = 25,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """External catalog candidates (with 30s previews) to confirm + request.
    Results the user already has in their library are flagged `owned`."""
    results = await catalog.search(http_client(), q, limit)
    # Best-effort: mark tracks already in the user's Navidrome library.
    try:
        sub = await navidrome_for(user.id, db)
        library = await sub.search3_songs(q, 60)
        catalog.mark_owned(results, library)
    except Exception:
        for r in results:
            r.setdefault("owned", False)
    return {"query": q, "results": results}


# A few seconds of audio is all Shazam needs; cap it so a bad client can't
# stream us an album.
_MAX_CLIP_BYTES = 6 * 1024 * 1024


@router.post("/identify")
async def identify_clip(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Recognise a song from a short recorded clip ("what's playing?").

    Returns the match plus ordinary catalogue results for it, so the app can
    preview, see whether it's already in the library, or request a download —
    the same flow as a typed search.
    """
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty recording")
    if len(data) > _MAX_CLIP_BYTES:
        raise HTTPException(status_code=413, detail="Recording too long")

    suffix = "." + (file.filename or "clip.m4a").rsplit(".", 1)[-1].lower()[:8]
    match = await identify.recognize(data, suffix)
    if match is None:
        return {"match": None, "results": []}

    results = await identify.candidates(http_client(), match)
    # Same ownership marking as /catalog/search, so a recognised song the user
    # already has is shown as playable rather than downloadable.
    try:
        sub = await navidrome_for(user.id, db)
        library = await sub.search3_songs(
            f"{match['artist']} {match['title']}", 60
        )
        catalog.mark_owned(results, library)
        catalog.mark_owned([match], library)
    except Exception:
        for r in results:
            r.setdefault("owned", False)
    return {"match": match, "results": results}


@router.get("/explore/home")
async def explore_home(
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Charts (AU + worldwide), the user's top artists, and new releases from
    artists they follow — the Explore landing page."""
    try:
        sub = await navidrome_for(user.id, db)
    except Exception:
        sub = None
    data = await explore.home(http_client(), sub)
    # Flag chart tracks we've already downloaded (owned = playable) and whether
    # they've been kept (moved to the permanent library).
    try:
        om = await charts_sync.owned_map()
        for key in ("australia", "worldwide"):
            for t in data.get(key, []):
                k = charts_sync._key(t["artist"], t["title"])
                t["owned"] = k in om
                t["kept"] = om.get(k, False)
    except Exception:
        pass
    # Keep the rotating Charts folder topped up (throttled; runs in background).
    background.add_task(charts_sync.maybe_sync)
    return data


class KeepBody(BaseModel):
    artist: str
    title: str


@router.post("/explore/keep")
async def explore_keep(
    body: KeepBody, _: User = Depends(get_current_user)
):
    """Promote a downloaded chart track into the permanent library so rotation
    won't delete it."""
    ok = await charts_sync.keep(body.artist, body.title)
    return {"kept": ok}


class DownloadBody(BaseModel):
    title: str
    artist: str
    album: str | None = None


def _req_json(r: DownloadRequest) -> dict:
    return {
        "id": r.id,
        "artist": r.artist,
        "title": r.title,
        "album": r.album,
        "status": r.status,
        "matchedFile": r.slskd_filename,
        "error": r.error,
    }


@router.post("/catalog/request")
async def catalog_request(
    body: DownloadBody,
    background: BackgroundTasks,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Queue a track to acquire and kick off slskd (Soulseek) fulfilment: search
    → pick the best file → enqueue the download. Status is tracked on the row
    and exposed via GET /requests."""
    req = DownloadRequest(
        user_id=user.id,
        artist=body.artist,
        title=body.title,
        album=body.album,
        status="pending",
    )
    db.add(req)
    await db.commit()
    await db.refresh(req)
    # Fulfil in the background so the app gets an immediate ack.
    background.add_task(fulfill.fulfill_request, req.id)
    return {"status": "queued", "id": req.id, **_req_json(req)}


@router.get("/requests")
async def list_requests(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    rows = (
        (
            await db.execute(
                select(DownloadRequest)
                .where(DownloadRequest.user_id == user.id)
                .order_by(DownloadRequest.created_at.desc())
                .limit(100)
            )
        )
        .scalars()
        .all()
    )
    return {"requests": [_req_json(r) for r in rows]}
