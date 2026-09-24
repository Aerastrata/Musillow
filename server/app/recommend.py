"""Navidrome-backed recommendations (per user).

Built from the user's own library (play counts, stars, recency) so it works from
day one, then bent by the taste they've shown inside Musillow itself — see
[taste]. No Troi/ListenBrainz account required: two people can share a server and
still get genuinely different results, because both halves of the score are
per-user.
"""
import math
import random
import time

from . import lb_discover
from .subsonic import Subsonic
from .taste import EMPTY, Taste

_DAY = 86400.0


def _age_days(ts: float | None) -> float | None:
    return (time.time() - ts) / _DAY if ts else None


def _recency_weight(last_played: float | None, half_life_days: float = 30.0) -> float:
    if not last_played:
        return 0.0
    age = (time.time() - last_played) / _DAY
    return math.exp(-age / half_life_days)


def _score(song: dict, taste: Taste = EMPTY) -> float:
    """How strongly to favour a song: how much it's been played, adjusted by
    what the user has told us in the app."""
    base = song["playCount"] * (0.5 + _recency_weight(song["lastPlayed"]))
    return base + taste.boost(song)


async def _played_pool(sub: Subsonic, albums: int = 40) -> list[dict]:
    album_list = await sub.album_list2("frequent", size=albums)
    pool: dict[str, dict] = {}
    for album in album_list:
        for song in await sub.album_songs(str(album["id"])):
            pool[song["id"]] = song
    return list(pool.values())


async def quick_picks(
    sub: Subsonic, taste: Taste = EMPTY, pool: list[dict] | None = None
) -> dict:
    # Building the pool costs ~40 upstream calls, so callers composing several
    # sections at once (the /home aggregate) pass in one they already have.
    pool = pool if pool is not None else await _played_pool(sub)
    starred = await sub.starred_songs()

    replay = sorted(taste.keep(pool), key=lambda s: _score(s, taste), reverse=True)[:8]
    replay_ids = {s["id"] for s in replay}

    forgotten = [
        s for s in taste.keep(starred)
        if s["lastPlayed"] is None or (_age_days(s["lastPlayed"]) or 0) >= 90
    ]
    forgotten.sort(key=lambda s: s["lastPlayed"] or 0)
    forgotten = forgotten[:8]

    wildcard = [
        s for s in taste.keep(pool)
        if s["playCount"] >= 5
        and (s["lastPlayed"] is None or (_age_days(s["lastPlayed"]) or 0) >= 180
        )
        and s["id"] not in replay_ids
    ]
    wildcard.sort(key=lambda s: s["playCount"], reverse=True)
    wildcard = wildcard[:8]

    return {
        "rows": [
            {"source": "Replay Mix", "tracks": replay},
            {"source": "Liked but Forgotten", "tracks": forgotten},
            {"source": "Wildcard", "tracks": wildcard},
        ]
    }


_DOW = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
]


async def discover_playlists(sub: Subsonic, taste: Taste = EMPTY) -> list[dict]:
    """Library-backed "made for you" playlists for the home screen. All tracks
    are already in the library, so these are instantly playable (unlike the
    download-and-rotate discovery playlists)."""
    pool = taste.keep(await _played_pool(sub))
    starred = taste.keep(await sub.starred_songs())
    out: list[dict] = []

    if pool:
        # Daily Mix — one per weekday, all seven surfaced at once. Each is
        # deterministic for (week, weekday) so it's stable through its day and
        # rotates when that weekday comes around again. Today's leads the row.
        top = sorted(pool, key=lambda s: _score(s, taste), reverse=True)[:120]
        today = int(time.time() // _DAY) % 7
        week = int(time.time() // (_DAY * 7))
        for offset in range(7):
            d = (today + offset) % 7
            rnd = random.Random(week * 7 + d)
            picks = list(top)
            rnd.shuffle(picks)
            out.append({
                "key": f"daily-{_DOW[d].lower()}",
                "title": f"{_DOW[d]} Mix",
                "subtitle": "Made for you today" if offset == 0 else _DOW[d],
                "tracks": picks[:30],
            })

        # On Repeat — recent heavy rotation.
        on_repeat = [
            s for s in pool
            if s["playCount"] >= 3 and _recency_weight(s["lastPlayed"]) > 0.25
        ]
        on_repeat.sort(
            key=lambda s: s["playCount"] * (_recency_weight(s["lastPlayed"]) + 0.1)
            + taste.boost(s),
            reverse=True,
        )
        out.append({
            "key": "on-repeat",
            "title": "On Repeat",
            "subtitle": "Songs you keep coming back to",
            "tracks": on_repeat[:30],
        })

        # Weekly Jams — your top tracks by play count.
        weekly = sorted(
            pool, key=lambda s: s["playCount"] + taste.boost(s), reverse=True
        )[:30]
        out.append({
            "key": "weekly-jams",
            "title": "Weekly Jams",
            "subtitle": "Your most-played this week",
            "tracks": weekly,
        })

    # Forgotten Faves — starred songs you haven't played in a while.
    forgotten = [
        s for s in starred
        if s["lastPlayed"] is None or (_age_days(s["lastPlayed"]) or 0) >= 60
    ]
    forgotten.sort(key=lambda s: s["lastPlayed"] or 0)
    if forgotten:
        out.append({
            "key": "forgotten-faves",
            "title": "Forgotten Faves",
            "subtitle": "Liked songs you've drifted from",
            "tracks": forgotten[:30],
        })

    return [p for p in out if p["tracks"]]


NATIVE_PLAYLISTS = {"replay", "forgotten", "wildcard", "daily", "discover"}


async def playlist(
    sub: Subsonic, ptype: str, size: int = 50, taste: Taste = EMPTY
) -> list[dict] | None:
    if ptype == "discover":
        # ListenBrainz similar-artist discovery, resolved to the user's library.
        pool = await _played_pool(sub)
        found = await lb_discover.discover(sub, pool, size)
        return taste.keep(found or [])
    if ptype == "replay":
        pool = taste.keep(await _played_pool(sub))
        return sorted(pool, key=lambda s: _score(s, taste), reverse=True)[:size]
    if ptype == "forgotten":
        starred = taste.keep(await sub.starred_songs())
        forgotten = [
            s for s in starred
            if s["lastPlayed"] is None or (_age_days(s["lastPlayed"]) or 0) >= 90
        ]
        forgotten.sort(key=lambda s: s["lastPlayed"] or 0)
        return forgotten[:size]
    if ptype == "wildcard":
        pool = taste.keep(await _played_pool(sub))
        wildcard = [
            s for s in pool
            if s["playCount"] >= 5
            and (s["lastPlayed"] is None or (_age_days(s["lastPlayed"]) or 0) >= 180)
        ]
        wildcard.sort(key=lambda s: s["playCount"], reverse=True)
        return wildcard[:size]
    if ptype == "daily":
        return taste.keep(await sub.random_songs(size))
    return None
