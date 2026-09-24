"""Fulfil download requests through slskd (Soulseek).

For each request: search slskd for "artist title", wait for the async Soulseek
search to complete, score the returned files, and enqueue the best one. Status
on the DownloadRequest row tracks progress so the app can show it.
"""
import asyncio
import logging
import os
import re
import shutil

from sqlalchemy import select

from . import slskd
from .config import settings
from .db import SessionLocal
from .http import client as http_client
from .models import DownloadRequest
from .services import navidrome_for

log = logging.getLogger("musillow.fulfill")

_AUDIO = (".flac", ".mp3", ".m4a", ".ogg", ".opus", ".wav")
_SEARCH_TIMEOUT = 25.0  # seconds to wait for Soulseek responses
_MIN_SIZE = 1_200_000  # ignore tiny files (samples/clips)


def _tokens(s: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 1}


def _basename(path: str) -> str:
    return re.split(r"[\\/]", path)[-1]


def _ext_rank(name: str) -> int:
    n = name.lower()
    if n.endswith(".flac"):
        return 3
    if n.endswith(".mp3") or n.endswith(".m4a"):
        return 2
    return 1


def _score(resp: dict, f: dict, title_tok: set[str], artist_tok: set[str]):
    """Return a sortable score tuple, or None if the file is a poor match."""
    name = _basename(f.get("filename", ""))
    lname = name.lower()
    if not lname.endswith(_AUDIO):
        return None
    if (f.get("size") or 0) < _MIN_SIZE:
        return None
    ftok = _tokens(name)
    # Require most of the title's words to appear in the filename.
    if title_tok and len(title_tok & ftok) < max(1, len(title_tok) - 1):
        return None
    artist_hit = 1 if artist_tok & ftok else 0
    free = 1 if resp.get("hasFreeUploadSlot") else 0
    queue = resp.get("queueLength") or 0
    speed = resp.get("uploadSpeed") or 0
    bitrate = f.get("bitRate") or 0
    # Higher is better; queue negated so shorter queues win.
    return (
        artist_hit,
        free,
        _ext_rank(name),
        bitrate,
        -queue,
        speed,
    )


def _rank_candidates(responses: list[dict], artist: str, title: str) -> list[tuple]:
    """Best-first list of (username, filename, size) matches so we can try the
    next one when a peer is offline or rejects the download."""
    title_tok = _tokens(title)
    artist_tok = _tokens(artist)
    scored = []
    for resp in responses:
        for f in resp.get("files", []):
            sc = _score(resp, f, title_tok, artist_tok)
            if sc is None:
                continue
            scored.append(
                (sc, resp.get("username"), f.get("filename"), f.get("size") or 0)
            )
    scored.sort(key=lambda x: x[0], reverse=True)
    return [(u, fn, sz) for _, u, fn, sz in scored]


async def _set(session, req: DownloadRequest, **fields):
    for k, v in fields.items():
        setattr(req, k, v)
    await session.commit()


def _transfer_state(downloads: list[dict], username: str, filename: str):
    for u in downloads:
        if u.get("username") != username:
            continue
        for d in u.get("directories", []):
            for f in d.get("files", []):
                if f.get("filename") == filename:
                    return f.get("state", "")
    return None


async def _await_completion(client, username, filename, timeout=600.0):
    """True on success, False on Soulseek failure, None on timeout."""
    waited = 0.0
    while waited < timeout:
        await asyncio.sleep(5.0)
        waited += 5.0
        try:
            state = _transfer_state(
                await slskd.get_downloads(client), username, filename
            )
        except Exception:
            continue
        if not state:
            continue
        low = state.lower()
        if "succeeded" in low:
            return True
        if any(x in low for x in ("errored", "cancelled", "failed", "rejected")):
            return False
    return None


def _find_local(filename: str) -> str | None:
    base = _basename(filename)
    for root, _, files in os.walk(settings.downloads_dir):
        if base in files:
            return os.path.join(root, base)
    return None


def _move_to(local_path: str, dest_base: str) -> str:
    # Keep the album folder so the library stays tidy; Navidrome reads tags
    # regardless, so exact structure doesn't matter for playback.
    parent = os.path.basename(os.path.dirname(local_path))
    dest_dir = (
        os.path.join(dest_base, parent)
        if parent and parent != os.path.basename(settings.downloads_dir)
        else dest_base
    )
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(local_path))
    shutil.move(local_path, dest)
    return dest


def _move_to_library(local_path: str) -> str:
    return _move_to(local_path, settings.library_dir)


async def download_track_to(
    client, artist: str, title: str, dest_base: str
) -> str | None:
    """Search Soulseek for "artist title", download the best working source,
    and move it under [dest_base]. Returns the final path, or None. Reusable by
    the charts sync (no DownloadRequest row involved)."""
    query = f"{artist} {title}".strip()
    sid = await slskd.create_search(client, query)
    if not sid:
        return None
    waited = 0.0
    while waited < _SEARCH_TIMEOUT:
        await asyncio.sleep(2.0)
        waited += 2.0
        state = await slskd.search_state(client, sid)
        st = (state.get("state") or "").lower()
        if "completed" in st and (state.get("responseCount") or 0) > 0:
            break
    responses = await slskd.search_responses(client, sid)
    for username, filename, size in _rank_candidates(responses, artist, title)[:6]:
        if not await slskd.enqueue_download(client, username, filename, size):
            continue
        done = await _await_completion(client, username, filename, timeout=120.0)
        if done is True:
            local = _find_local(filename)
            if local:
                try:
                    return _move_to(local, dest_base)
                except Exception:
                    return None
    return None


async def _import_file(session, req: DownloadRequest, filename: str) -> bool:
    """Move a finished download into the library and trigger a rescan."""
    local = _find_local(filename)
    if local:
        try:
            _move_to_library(local)
        except Exception as e:
            await _set(session, req, status="failed", error=f"move: {e}")
            return False
    # Best-effort: trigger a Navidrome rescan so it becomes playable now.
    try:
        sub = await navidrome_for(req.user_id, session)
        await sub.start_scan()
    except Exception:
        pass
    await _set(session, req, status="completed")
    return True


async def fulfill_request(request_id: int) -> None:
    """Run one request end-to-end. Owns its own DB session."""
    async with SessionLocal() as session:
        req = (
            await session.execute(
                select(DownloadRequest).where(DownloadRequest.id == request_id)
            )
        ).scalar_one_or_none()
        if req is None:
            return
        client = http_client()
        try:
            await _set(session, req, status="searching", error=None)
            query = f"{req.artist} {req.title}".strip()
            sid = await slskd.create_search(client, query)
            if not sid:
                await _set(session, req, status="failed", error="search failed")
                return
            # Poll until Soulseek finishes gathering (or we time out).
            waited = 0.0
            while waited < _SEARCH_TIMEOUT:
                await asyncio.sleep(2.0)
                waited += 2.0
                state = await slskd.search_state(client, sid)
                st = (state.get("state") or "").lower()
                if "completed" in st and (state.get("responseCount") or 0) > 0:
                    break
            responses = await slskd.search_responses(client, sid)
            candidates = _rank_candidates(responses, req.artist, req.title)
            if not candidates:
                await _set(session, req, status="no_match")
                return
            # Try candidates in order: Soulseek peers are often offline or
            # reject/queue, so fall through to the next until one downloads.
            for username, filename, size in candidates[:6]:
                ok = await slskd.enqueue_download(client, username, filename, size)
                if not ok:
                    continue
                await _set(
                    session,
                    req,
                    status="downloading",
                    slskd_username=username,
                    slskd_filename=filename,
                )
                done = await _await_completion(
                    client, username, filename, timeout=120.0
                )
                if done is True:
                    await _import_file(session, req, filename)
                    return
                # errored / rejected / timed out → try the next candidate
            await _set(
                session, req, status="failed", error="no working source found"
            )
        except Exception as e:  # never let a bad request kill the worker
            log.exception("fulfil failed for request %s", request_id)
            try:
                await _set(session, req, status="failed", error=str(e)[:400])
            except Exception:
                pass


async def process_pending() -> None:
    """Re-drive requests left mid-flight by a restart: fresh 'pending' ones get
    fulfilled; 'downloading' ones get their import/rescan finished."""
    async with SessionLocal() as session:
        rows = (
            (
                await session.execute(
                    select(DownloadRequest).where(
                        DownloadRequest.status.in_(("pending", "downloading"))
                    )
                )
            )
            .scalars()
            .all()
        )
        pending = [r.id for r in rows if r.status == "pending"]
        resuming = [
            (r.id, r.slskd_username, r.slskd_filename)
            for r in rows
            if r.status == "downloading" and r.slskd_username and r.slskd_filename
        ]
    for rid in pending:
        await fulfill_request(rid)
    # Finish anything that was mid-download when we restarted.
    client = http_client()
    for rid, username, filename in resuming:
        done = await _await_completion(client, username, filename, timeout=120.0)
        async with SessionLocal() as session:
            req = (
                await session.execute(
                    select(DownloadRequest).where(DownloadRequest.id == rid)
                )
            ).scalar_one_or_none()
            if req is None:
                continue
            if done is True:
                await _import_file(session, req, filename)
            elif done is False:
                await _set(session, req, status="failed", error="download failed")
