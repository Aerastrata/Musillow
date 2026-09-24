"""Acoustic song recognition ("what's playing?").

The phone records a few seconds of audio and posts it here; we fingerprint it
against Shazam's catalogue via `shazamio`, which needs no API key and no account
— important, because Musillow is meant to be cloned and run by anyone without
signing up for a pile of third-party services.

The recognised artist/title is then run back through the normal iTunes catalogue
search, so a Shazam hit arrives at the app as an ordinary search result: same
30-second preview, same `owned` flag, same "request download" button.
"""
import asyncio
import tempfile

import httpx

from . import catalog

# Recognition is CPU-bound fingerprinting and shells out to ffmpeg; one at a
# time keeps a burst of taps from starving the event loop.
_lock = asyncio.Semaphore(2)


def _artwork(track: dict) -> str | None:
    images = track.get("images") or {}
    return images.get("coverart") or images.get("background")


def _year(track: dict) -> str | None:
    """Release year, which Shazam buries in the metadata section."""
    for section in track.get("sections") or []:
        for item in section.get("metadata") or []:
            if str(item.get("title", "")).lower() in {"released", "release date"}:
                text = str(item.get("text") or "")
                return text[:4] if text[:4].isdigit() else None
    return None


def _match(track: dict) -> dict:
    """Normalise a Shazam track into the shape the app's search results use."""
    return {
        "id": str(track.get("key") or ""),
        "title": str(track.get("title") or "Unknown"),
        "artist": str(track.get("subtitle") or "Unknown artist"),
        "album": None,
        "artworkUrl": _artwork(track),
        "previewUrl": None,
        "year": _year(track),
        "owned": False,
        "kept": False,
    }


async def recognize(data: bytes, suffix: str = ".m4a") -> dict | None:
    """Fingerprint an audio clip. Returns the normalised match, or None."""
    from shazamio import Shazam

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as tmp:
        tmp.write(data)
        tmp.flush()
        async with _lock:
            try:
                out = await Shazam().recognize(tmp.name)
            except Exception:
                return None
    track = (out or {}).get("track")
    if not track:
        return None
    return _match(track)


async def candidates(
    client: httpx.AsyncClient, match: dict, limit: int = 10
) -> list[dict]:
    """Catalogue results for a recognised track, best match first.

    Going back through iTunes is what earns the 30s preview and the artwork the
    rest of the app expects; the Shazam match itself carries neither in a form
    the download flow can use.
    """
    query = f"{match['artist']} {match['title']}".strip()
    results = await catalog.search(client, query, limit)
    if not results:
        return []
    # Prefer an exact title match so the tapped song leads, not a remix.
    target = catalog._words(match["title"])
    results.sort(key=lambda r: catalog._words(r.get("title")) != target)
    return results
