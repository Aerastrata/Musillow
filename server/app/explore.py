"""Explore home data: charts, top artists, new releases.

Charts come from the free Apple Music RSS feeds; each chart track is enriched
with a 30s preview via a single batched iTunes lookup so it plugs straight into
the same preview + request flow as search. New releases are recent albums by the
user's most-played artists. Top artists come from the user's own library.
"""
import time
from collections import defaultdict

import httpx

from . import catalog, recommend
from .subsonic import Subsonic

_RSS = "https://rss.applemarketingtools.com/api/v2/{c}/music/most-played/{n}/songs.json"
_LOOKUP = "https://itunes.apple.com/lookup"
_SEARCH = "https://itunes.apple.com/search"

# Charts are identical for everyone — cache briefly to stay snappy.
_chart_cache: dict[str, tuple[float, list[dict]]] = {}
_CHART_TTL = 1800.0


def _art(url: str | None) -> str | None:
    if not url:
        return None
    return url.replace("100x100bb", "300x300bb")


async def charts(client: httpx.AsyncClient, country: str = "au", limit: int = 20):
    cached = _chart_cache.get(country)
    if cached and (time.time() - cached[0]) < _CHART_TTL:
        return cached[1][:limit]
    try:
        r = await client.get(_RSS.format(c=country, n=limit), timeout=15)
        rows = r.json().get("feed", {}).get("results", []) if r.status_code == 200 else []
    except Exception:
        rows = []
    ids = [x["id"] for x in rows if x.get("id")]
    looked: dict[str, dict] = {}
    if ids:
        try:
            lk = await client.get(
                _LOOKUP, params={"id": ",".join(ids), "entity": "song"}, timeout=15
            )
            for x in lk.json().get("results", []):
                if x.get("trackId"):
                    looked[str(x["trackId"])] = x
        except Exception:
            pass
    out = []
    for x in rows:
        song = looked.get(str(x["id"]))
        if song and song.get("previewUrl"):
            out.append(catalog._norm(song))
        else:  # RSS-only fallback (no preview, still requestable)
            out.append(
                {
                    "id": str(x.get("id", "")),
                    "title": x.get("name", "Unknown"),
                    "artist": x.get("artistName", "Unknown artist"),
                    "album": None,
                    "artworkUrl": _art(x.get("artworkUrl100")),
                    "previewUrl": None,
                    "year": None,
                }
            )
    _chart_cache[country] = (time.time(), out)
    return out[:limit]


async def top_artists(sub: Subsonic, pool: list[dict], limit: int = 5):
    agg: dict[str, list] = defaultdict(lambda: [0, None])
    for s in pool:
        a = s.get("artist")
        if not a or a == "Unknown artist":
            continue
        agg[a][0] += s["playCount"]
        if agg[a][1] is None and s.get("coverArt"):
            agg[a][1] = s["coverArt"]
    ranked = sorted(agg.items(), key=lambda kv: kv[1][0], reverse=True)[:limit]
    return [{"name": n, "coverArt": v[1]} for n, v in ranked]


# New releases mean one iTunes lookup per artist, which is far too slow to
# repeat on every home load. Keyed by the artist set, refreshed hourly.
_release_cache: dict[str, tuple[float, list[dict]]] = {}
_RELEASE_TTL = 3600.0


async def new_releases(client: httpx.AsyncClient, artists: list[str], limit: int = 20):
    cache_key = "|".join(sorted(artists))
    cached = _release_cache.get(cache_key)
    if cached and (time.time() - cached[0]) < _RELEASE_TTL:
        return cached[1][:limit]
    out: list[dict] = []
    seen: set = set()
    for name in artists:
        try:
            r = await client.get(
                _SEARCH,
                params={
                    "term": name,
                    "entity": "album",
                    "attribute": "artistTerm",
                    "limit": 6,
                },
                timeout=15,
            )
            albums = [a for a in r.json().get("results", []) if a.get("releaseDate")]
        except Exception:
            continue
        albums.sort(key=lambda a: a["releaseDate"], reverse=True)
        for a in albums[:3]:
            cid = a.get("collectionId")
            if cid in seen:
                continue
            seen.add(cid)
            out.append(
                {
                    "id": str(cid or ""),
                    "title": a.get("collectionName", "Unknown"),
                    "artist": a.get("artistName", "Unknown artist"),
                    "artworkUrl": _art(a.get("artworkUrl100")),
                    "year": (a.get("releaseDate") or "")[:4] or None,
                }
            )
    out.sort(key=lambda a: a.get("year") or "", reverse=True)
    _release_cache[cache_key] = (time.time(), out)
    return out[:limit]


def world_top_artists(chart_tracks: list[dict], limit: int = 5) -> list[dict]:
    """Most-charting distinct artists worldwide, in chart order, with art."""
    seen: dict[str, str | None] = {}
    for t in chart_tracks:
        a = t.get("artist")
        if a and a not in seen:
            seen[a] = t.get("artworkUrl")
    return [{"name": n, "artworkUrl": art} for n, art in list(seen.items())[:limit]]


async def home(client: httpx.AsyncClient, sub: Subsonic | None) -> dict:
    tops: list[dict] = []
    releases: list[dict] = []
    au = await charts(client, "au", 20)
    ww = await charts(client, "us", 20)
    if sub is not None:
        try:
            pool = await recommend._played_pool(sub)
            tops = await top_artists(sub, pool, 5)
            releases = await new_releases(client, [t["name"] for t in tops], 20)
        except Exception:
            pass
    return {
        "topArtists": tops,
        "worldArtists": world_top_artists(ww, 5),
        "australia": au,
        "worldwide": ww,
        "newReleases": releases,
    }
