"""ListenBrainz-backed discovery.

Turns the user's most-played artists into *new* suggestions by asking
ListenBrainz which artists are similar (global collaborative-filtering data),
then resolving those artists back to songs the user actually owns in Navidrome
so every pick is immediately playable. Token-less: uses only the public
MusicBrainz + ListenBrainz labs endpoints.

Everything here is best-effort — any network failure yields an empty list so it
can never break the (library-only) quick-picks that ship alongside it.
"""
import asyncio
import time
from collections import defaultdict

import httpx

from .http import client as http_client
from .subsonic import Subsonic

# MusicBrainz asks for a descriptive UA and ~1 req/sec. No personal data.
_UA = "Musillow/1.0 (self-hosted music discovery)"
_MB = "https://musicbrainz.org/ws/2"
_LB_SIMILAR = "https://labs.api.listenbrainz.org/similar-artists/json"
# Current ListenBrainz session-based similarity model (see labs API).
_LB_ALGO = (
    "session_based_days_7500_session_300_contribution_5_"
    "threshold_10_limit_100_filter_True_skip_30"
)

# Process-wide caches. MBID lookups rarely change; discovery results are
# refreshed on a TTL so repeat home-screen loads stay fast.
_mbid_cache: dict[str, str | None] = {}
_result_cache: dict[str, tuple[float, list[dict]]] = {}
_RESULT_TTL = 6 * 3600.0
_mb_lock = asyncio.Lock()  # serialise MusicBrainz calls (rate limit)


async def _mb_artist_mbid(client: httpx.AsyncClient, name: str) -> str | None:
    key = name.lower()
    if key in _mbid_cache:
        return _mbid_cache[key]
    async with _mb_lock:
        # Re-check inside the lock in case a concurrent call filled it.
        if key in _mbid_cache:
            return _mbid_cache[key]
        mbid = None
        try:
            r = await client.get(
                f"{_MB}/artist/",
                params={"query": f'artist:"{name}"', "fmt": "json", "limit": 1},
                headers={"User-Agent": _UA},
                timeout=15,
            )
            if r.status_code == 200:
                artists = r.json().get("artists") or []
                if artists:
                    mbid = artists[0].get("id")
        except Exception:
            mbid = None
        _mbid_cache[key] = mbid
        await asyncio.sleep(1.1)  # be polite to MusicBrainz
        return mbid


async def _lb_similar(client: httpx.AsyncClient, mbid: str) -> list[tuple[str, float]]:
    try:
        r = await client.get(
            _LB_SIMILAR,
            params={"artist_mbids": mbid, "algorithm": _LB_ALGO},
            headers={"User-Agent": _UA},
            timeout=15,
        )
        if r.status_code != 200:
            return []
        return [
            (a["name"], float(a.get("score", 0)))
            for a in r.json()
            if a.get("name")
        ]
    except Exception:
        return []


async def _top_artists(sub: Subsonic, pool: list[dict], limit: int = 8) -> list[str]:
    by_artist: dict[str, int] = defaultdict(int)
    for s in pool:
        if s["artist"] and s["artist"] != "Unknown artist":
            by_artist[s["artist"]] += s["playCount"]
    ranked = sorted(by_artist.items(), key=lambda kv: kv[1], reverse=True)
    return [a for a, _ in ranked[:limit]]


async def discover(sub: Subsonic, pool: list[dict], size: int = 12) -> list[dict]:
    """Songs the user owns by artists similar to their favourites.

    [pool] is the already-fetched played-songs pool (reused from quick-picks so
    we don't hit Navidrome twice).
    """
    cache_key = f"{sub.base}|{sub.username}"
    cached = _result_cache.get(cache_key)
    if cached and (time.time() - cached[0]) < _RESULT_TTL:
        return cached[1][:size]

    client = http_client()
    top = await _top_artists(sub, pool)
    if not top:
        return []
    seeds = {a.lower() for a in top}
    owned = {s["artist"].lower() for s in pool}

    # Aggregate similar-artist scores across all the seeds.
    agg: dict[str, float] = defaultdict(float)
    for name in top:
        mbid = await _mb_artist_mbid(client, name)
        if not mbid:
            continue
        for sim_name, score in await _lb_similar(client, mbid):
            if sim_name.lower() in seeds:
                continue
            agg[sim_name] += score
    if not agg:
        return []
    ranked = [n for n, _ in sorted(agg.items(), key=lambda kv: kv[1], reverse=True)]

    # Resolve to the user's library, keeping it varied: at most a couple of
    # tracks per similar artist so one well-stocked artist can't fill the row.
    # A second pass relaxes the per-artist cap only if we'd otherwise fall short.
    per_artist_cap = 2
    picks: list[dict] = []
    seen_ids: set[str] = set()
    # owned similar artists, in similarity-rank order
    owned_ranked = [a for a in ranked if a.lower() in owned]
    songs_by_artist: dict[str, list[dict]] = {}
    for artist in owned_ranked:
        try:
            songs = await sub.search3_songs(artist, song_count=25)
        except Exception:
            continue
        mine = [s for s in songs if s["artist"].lower() == artist.lower()]
        mine.sort(key=lambda s: s["playCount"], reverse=True)
        songs_by_artist[artist] = mine

    for cap in (per_artist_cap, size):  # tight pass, then relaxed backfill
        for artist in owned_ranked:
            taken = 0
            for s in songs_by_artist.get(artist, []):
                if len(picks) >= size:
                    break
                if s["id"] in seen_ids or taken >= cap:
                    continue
                seen_ids.add(s["id"])
                picks.append(s)
                taken += 1
        if len(picks) >= size:
            break

    _result_cache[cache_key] = (time.time(), picks)
    return picks
