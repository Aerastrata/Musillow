"""Full Navidrome library proxy.

The client only ever talks to this backend: every bit of metadata, audio, and
cover art is fetched here using the user's stored Navidrome connector, so the
phone never needs to reach Navidrome directly.
"""
import os

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..db import get_db
from ..deps import get_current_user, get_current_user_media
from ..images import sniff_image_mime
from ..models import PlaylistCover, User
from ..proxy import stream_proxy
from ..schemas import PlaylistAddIn, PlaylistCreateIn, PlaylistUpdateIn
from ..services import navidrome_for
from ..subsonic import SubsonicError

router = APIRouter(tags=["library"])


def _wrap(exc: SubsonicError) -> HTTPException:
    return HTTPException(status_code=502, detail=f"Navidrome error: {exc}")


def _cover_path(user_id: int, playlist_id: str) -> str:
    """On-disk location of a user's custom cover for [playlist_id]. The
    playlist id is sanitised so it can't escape the covers directory."""
    safe = "".join(c for c in playlist_id if c.isalnum() or c in "-_")
    return os.path.join(settings.covers_dir, f"{user_id}_{safe}")


async def _custom_cover_ids(db: AsyncSession, user_id: int) -> set[str]:
    """Playlist ids for which this user has a stored custom cover."""
    rows = await db.execute(
        select(PlaylistCover.playlist_id).where(PlaylistCover.user_id == user_id)
    )
    return {r[0] for r in rows.all()}


async def _save_custom_cover(
    db: AsyncSession, user_id: int, playlist_id: str, data: bytes, mime: str, kind: str
) -> None:
    """Write cover bytes to disk and upsert the tracking row."""
    os.makedirs(settings.covers_dir, exist_ok=True)
    with open(_cover_path(user_id, playlist_id), "wb") as f:
        f.write(data)
    existing = await db.scalar(
        select(PlaylistCover).where(
            PlaylistCover.user_id == user_id,
            PlaylistCover.playlist_id == playlist_id,
        )
    )
    if existing:
        existing.mime = mime
        existing.kind = kind
    else:
        db.add(
            PlaylistCover(
                user_id=user_id, playlist_id=playlist_id, mime=mime, kind=kind
            )
        )
    await db.commit()


async def _clear_custom_cover(
    db: AsyncSession, user_id: int, playlist_id: str
) -> None:
    """Drop a playlist's custom cover row and file, if any."""
    await db.execute(
        delete(PlaylistCover).where(
            PlaylistCover.user_id == user_id,
            PlaylistCover.playlist_id == playlist_id,
        )
    )
    await db.commit()
    try:
        os.remove(_cover_path(user_id, playlist_id))
    except FileNotFoundError:
        pass


# ---- Metadata --------------------------------------------------------------


@router.get("/library/random-songs")
async def random_songs(
    size: int = 200,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"songs": await sub.random_songs(size)}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/playlists")
async def playlists(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        lists = await sub.playlists()
    except SubsonicError as e:
        raise _wrap(e)
    custom = await _custom_cover_ids(db, user.id)
    for p in lists:
        p["hasCustomCover"] = str(p.get("id")) in custom
    return {"playlists": lists}


@router.get("/library/playlists/{playlist_id}")
async def playlist(
    playlist_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        data = await sub.playlist(playlist_id)
    except SubsonicError as e:
        raise _wrap(e)
    data["hasCustomCover"] = playlist_id in await _custom_cover_ids(db, user.id)
    return data


@router.post("/library/playlists")
async def create_playlist(
    body: PlaylistCreateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Playlist name is required")
    sub = await navidrome_for(user.id, db)
    try:
        return await sub.create_playlist(name, body.songIds)
    except SubsonicError as e:
        raise _wrap(e)


@router.put("/library/playlists/{playlist_id}")
async def update_playlist(
    playlist_id: str,
    body: PlaylistUpdateIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        if body.name is not None and body.name.strip():
            await sub.rename_playlist(playlist_id, body.name.strip())
        if body.songIds is not None:
            await sub.replace_playlist(playlist_id, body.songIds)
    except SubsonicError as e:
        raise _wrap(e)
    return {"ok": True}


@router.post("/library/playlists/{playlist_id}/songs")
async def add_to_playlist(
    playlist_id: str,
    body: PlaylistAddIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not body.songIds:
        raise HTTPException(status_code=400, detail="No songs given")
    sub = await navidrome_for(user.id, db)
    try:
        await sub.add_to_playlist(playlist_id, body.songIds)
    except SubsonicError as e:
        raise _wrap(e)
    return {"ok": True}


@router.delete("/library/playlists/{playlist_id}")
async def delete_playlist(
    playlist_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        await sub.delete_playlist(playlist_id)
    except SubsonicError as e:
        raise _wrap(e)
    await _clear_custom_cover(db, user.id, playlist_id)
    return {"ok": True}


@router.get("/library/albums")
async def albums(
    type: str = "alphabeticalByName",
    size: int = 100,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"albums": await sub.albums(type, size)}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/albums/{album_id}")
async def album(
    album_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return await sub.album(album_id)
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/artists")
async def artists(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"artists": await sub.artists()}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/artists/{artist_id}")
async def artist_albums(
    artist_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"albums": await sub.artist_albums(artist_id)}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/genres")
async def genres(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"genres": await sub.genres()}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/genres/{genre}")
async def songs_by_genre(
    genre: str,
    count: int = 200,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"songs": await sub.songs_by_genre(genre, count)}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/radio")
async def radio(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"stations": await sub.internet_radio_stations()}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/search")
async def search(
    q: str,
    count: int = 30,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"songs": await sub.search3_songs(q, count)}
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/starred")
async def starred(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    sub = await navidrome_for(user.id, db)
    try:
        return await sub.starred()
    except SubsonicError as e:
        raise _wrap(e)


@router.post("/library/star/{song_id}")
async def star(
    song_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        await sub.star(song_id)
    except SubsonicError as e:
        raise _wrap(e)
    return {"ok": True}


@router.post("/library/unstar/{song_id}")
async def unstar(
    song_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        await sub.unstar(song_id)
    except SubsonicError as e:
        raise _wrap(e)
    return {"ok": True}


@router.get("/library/lyrics/{song_id}")
async def lyrics(
    song_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return await sub.lyrics_by_song_id(song_id)
    except SubsonicError as e:
        raise _wrap(e)


@router.get("/library/similar/{song_id}")
async def similar(
    song_id: str,
    count: int = 30,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    try:
        return {"songs": await sub.similar_songs(song_id, count)}
    except SubsonicError as e:
        raise _wrap(e)


# ---- Custom playlist covers -------------------------------------------------

_MAX_COVER_BYTES = 8 * 1024 * 1024  # 8 MB


@router.put("/library/playlists/{playlist_id}/cover")
async def upload_playlist_cover(
    playlist_id: str,
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    if len(data) > _MAX_COVER_BYTES:
        raise HTTPException(status_code=413, detail="Image too large (max 8 MB)")
    # Identified from the bytes, not the declared Content-Type — see images.py.
    mime = sniff_image_mime(data)
    if mime is None:
        raise HTTPException(
            status_code=400, detail="Unsupported image type (use JPEG, PNG or WebP)"
        )
    await _save_custom_cover(db, user.id, playlist_id, data, mime, "upload")
    return {"ok": True}


@router.put("/library/playlists/{playlist_id}/cover-from-song/{song_id}")
async def set_playlist_cover_from_song(
    playlist_id: str,
    song_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Snapshot a song's cover art as the playlist's cover."""
    sub = await navidrome_for(user.id, db)
    try:
        data, mime = await sub.cover_bytes(song_id)
    except SubsonicError as e:
        raise _wrap(e)
    except Exception:
        raise HTTPException(status_code=502, detail="Couldn't fetch song art")
    if not data:
        raise HTTPException(status_code=404, detail="Song has no cover art")
    await _save_custom_cover(db, user.id, playlist_id, data, mime, "song")
    return {"ok": True}


@router.delete("/library/playlists/{playlist_id}/cover")
async def clear_playlist_cover(
    playlist_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await _clear_custom_cover(db, user.id, playlist_id)
    return {"ok": True}


@router.get("/library/playlist-cover/{playlist_id}")
async def playlist_cover(
    playlist_id: str,
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    row = await db.scalar(
        select(PlaylistCover).where(
            PlaylistCover.user_id == user.id,
            PlaylistCover.playlist_id == playlist_id,
        )
    )
    path = _cover_path(user.id, playlist_id)
    if row is None or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="No custom cover")
    return FileResponse(path, media_type=row.mime)


# ---- Media byte proxy (audio + cover art) ----------------------------------


@router.get("/stream/{song_id}")
async def stream(
    song_id: str,
    bitrate: int = 0,
    range: str | None = Header(default=None),
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    """Proxy the song's audio. [bitrate] (kbps) asks Navidrome to transcode
    down for the client's chosen streaming quality; 0 streams the original
    file untouched."""
    sub = await navidrome_for(user.id, db)
    extra: dict = {"id": song_id}
    if bitrate > 0:
        extra["maxBitRate"] = bitrate
        extra["format"] = "mp3"
    return await stream_proxy(
        sub.media_url("stream.view"),
        params=sub.media_params(extra),
        range_header=range,
    )


@router.get("/cover/{cover_id}")
async def cover(
    cover_id: str,
    size: int = 512,
    range: str | None = Header(default=None),
    user: User = Depends(get_current_user_media),
    db: AsyncSession = Depends(get_db),
):
    sub = await navidrome_for(user.id, db)
    return await stream_proxy(
        sub.media_url("getCoverArt.view"),
        params=sub.media_params({"id": cover_id, "size": size}),
        range_header=range,
    )
