"""Audiobookshelf proxy.

Mirrors the Navidrome arrangement: the client talks only to this backend, which
holds the user's ABS connector and relays metadata, progress, cover art and
audio. Nothing about the ABS server (its address, its token) ever reaches the
phone, so switching Musillow accounts switches audiobook libraries too.
"""
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..abs import AbsError
from ..db import get_db
from ..deps import get_current_user, get_current_user_media
from ..models import User
from ..proxy import stream_proxy
from ..services import abs_for, has_connector

router = APIRouter(prefix="/abs", tags=["audiobooks"])


def _wrap(exc: AbsError) -> HTTPException:
    return HTTPException(status_code=502, detail=f"Audiobookshelf error: {exc}")


@router.get("/status")
async def status(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    """Whether this account has a working ABS connector, and which library to
    use by default. The app calls this on account switch to decide whether the
    audiobook sections are available."""
    if not await has_connector(user.id, "abs", db):
        return {"connected": False, "libraryId": None}
    client = await abs_for(user.id, db)
    try:
        library_id = await client.book_library_id()
    except AbsError:
        return {"connected": False, "libraryId": None}
    return {"connected": True, "libraryId": library_id}


@router.get("/libraries")
async def libraries(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    client = await abs_for(user.id, db)
    try:
        return {"libraries": await client.libraries()}
    except AbsError as e:
        raise _wrap(e)


@router.get("/libraries/{library_id}/books")
async def books(
    library_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return {"books": await client.books(library_id)}
    except AbsError as e:
        raise _wrap(e)


@router.get("/libraries/{library_id}/authors")
async def authors(
    library_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return {"authors": await client.authors(library_id)}
    except AbsError as e:
        raise _wrap(e)


@router.get("/libraries/{library_id}/series")
async def series(
    library_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return {"series": await client.series(library_id)}
    except AbsError as e:
        raise _wrap(e)


@router.get("/authors/{author_id}/books")
async def author_books(
    author_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return {"books": await client.author_books(author_id)}
    except AbsError as e:
        raise _wrap(e)


@router.get("/in-progress")
async def in_progress(
    limit: int = 10,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Part-finished books, for the home screen's Continue listening row."""
    client = await abs_for(user.id, db)
    try:
        return {"books": await client.in_progress(limit)}
    except AbsError as e:
        raise _wrap(e)


@router.get("/items/{item_id}/tracks")
async def item_tracks(
    item_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return await client.book_tracks(item_id)
    except AbsError as e:
        raise _wrap(e)


@router.get("/items/{item_id}/progress")
async def get_progress(
    item_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        return await client.progress(item_id)
    except AbsError as e:
        raise _wrap(e)


class ProgressIn(BaseModel):
    currentTime: float
    duration: float
    isFinished: bool = False


@router.patch("/items/{item_id}/progress")
async def put_progress(
    item_id: str,
    body: ProgressIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    try:
        await client.update_progress(
            item_id,
            current_time=body.currentTime,
            duration=body.duration,
            is_finished=body.isFinished,
        )
    except AbsError as e:
        raise _wrap(e)
    return {"ok": True}


@router.get("/stats")
async def stats(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    client = await abs_for(user.id, db)
    try:
        return {"stats": await client.stats()}
    except AbsError as e:
        raise _wrap(e)


# ---- Media byte proxy (cover art, author images, audio) ---------------------


@router.get("/cover/{item_id}")
async def cover(
    item_id: str,
    width: int = 512,
    range: str | None = Header(default=None),
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    return await stream_proxy(
        client.cover_url(item_id),
        params={"width": width},
        headers=await client.auth_headers(),
        range_header=range,
    )


@router.get("/author-image/{author_id}")
async def author_image(
    author_id: str,
    width: int = 400,
    range: str | None = Header(default=None),
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    return await stream_proxy(
        client.author_image_url(author_id),
        params={"width": width},
        headers=await client.auth_headers(),
        range_header=range,
    )


@router.get("/audio/{item_id}/{ino}")
async def audio(
    item_id: str,
    ino: str,
    range: str | None = Header(default=None),
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    client = await abs_for(user.id, db)
    return await stream_proxy(
        client.audio_url(item_id, ino),
        headers=await client.auth_headers(),
        range_header=range,
    )
