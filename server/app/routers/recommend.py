from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from .. import recommend, taste as taste_mod
from ..db import get_db
from ..deps import get_current_user
from ..models import User
from ..services import navidrome_for
from ..subsonic import SubsonicError

router = APIRouter(tags=["recommend"])


async def _taste_for(user: User, db: AsyncSession, sub):
    """The user's learned taste, keyed to their own library. Never fatal — a
    signal-loading hiccup should degrade to plain library recommendations
    rather than emptying someone's home screen."""
    try:
        pool = await recommend._played_pool(sub)
        return await taste_mod.load(db, user.id, pool)
    except Exception:
        return taste_mod.EMPTY


@router.get("/quick-picks")
async def quick_picks(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        return await recommend.quick_picks(sub, await _taste_for(user, db, sub))
    except SubsonicError as e:
        raise HTTPException(status_code=502, detail=f"Navidrome error: {e}")


@router.get("/discover/playlists")
async def discover_playlists(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    """Library-backed 'made for you' playlists for the home screen."""
    sub = await navidrome_for(user.id, db)
    try:
        taste = await _taste_for(user, db, sub)
        return {"playlists": await recommend.discover_playlists(sub, taste)}
    except SubsonicError as e:
        raise HTTPException(status_code=502, detail=f"Navidrome error: {e}")


@router.get("/playlists/{ptype}")
async def playlists(
    ptype: str,
    size: int = 50,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        taste = await _taste_for(user, db, sub)
        tracks = await recommend.playlist(sub, ptype, size, taste)
    except SubsonicError as e:
        raise HTTPException(status_code=502, detail=f"Navidrome error: {e}")
    if tracks is None:
        raise HTTPException(
            status_code=501,
            detail=f"Playlist '{ptype}' not implemented yet (Troi patch pending).",
        )
    return {
        "type": ptype,
        "title": ptype.replace("_", " ").title(),
        "tracks": tracks,
    }
