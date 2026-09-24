"""External catalog search with 30-second previews (iTunes Search API).

Used by the Explore "search a song → pick the right version → request" flow.
iTunes is free, keyless, and returns artwork + a 30s preview URL for each hit,
which is exactly what's needed to confirm a track before sending it to SoulSync
for download. Results are *not* from the user's library — they're candidates to
acquire.
"""
import re

import httpx

_ITUNES = "https://itunes.apple.com/search"


def _words(s: str | None) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", (s or "").lower()))


def mark_owned(results: list[dict], library_songs: list[dict]) -> None:
    """Flag catalogue results the user already has: same (normalised) title and
    at least one shared artist word."""
    lib = [(_words(s.get("title")), _words(s.get("artist"))) for s in library_songs]
    for r in results:
        rt, ra = _words(r.get("title")), _words(r.get("artist"))
        r["owned"] = any(lt == rt and bool(la & ra) for lt, la in lib)


def _art(url: str | None, size: int = 300) -> str | None:
    # iTunes gives a 100px art URL; bump it to something usable.
    if not url:
        return None
    return url.replace("100x100bb", f"{size}x{size}bb")


def _norm(r: dict) -> dict:
    return {
        "id": str(r.get("trackId") or ""),
        "title": r.get("trackName") or "Unknown",
        "artist": r.get("artistName") or "Unknown artist",
        "album": r.get("collectionName"),
        "artworkUrl": _art(r.get("artworkUrl100")),
        "previewUrl": r.get("previewUrl"),
        "durationMs": r.get("trackTimeMillis"),
        "year": (r.get("releaseDate") or "")[:4] or None,
    }


async def search(client: httpx.AsyncClient, term: str, limit: int = 25) -> list[dict]:
    term = (term or "").strip()
    if not term:
        return []
    try:
        r = await client.get(
            _ITUNES,
            params={
                "term": term,
                "media": "music",
                "entity": "song",
                "limit": max(1, min(limit, 50)),
            },
            timeout=15,
        )
        if r.status_code != 200:
            return []
        results = r.json().get("results", [])
    except Exception:
        return []
    # Keep only rows we can actually preview.
    return [_norm(x) for x in results if x.get("previewUrl")]
