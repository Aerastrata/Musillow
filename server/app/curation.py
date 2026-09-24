"""Curated home-screen sections: the spotlight, album suggestions, mood rows.

Everything here is per-user and derived from the user's own library plus the
taste learned from their signals — no external service, nothing to sign up for.

The spotlight in particular is built from what the user has actually been
playing: the recent plays are the seeds, and the library is searched for songs
near them, so it follows a listening session rather than restating the same
all-time favourites.
"""
import asyncio
import datetime as dt
import time
from collections import defaultdict

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import FeaturedPlaylist, Signal
from .recommend import _recency_weight
from .subsonic import Subsonic
from .taste import EMPTY, Taste

_DAY = 86400.0

# The spotlight is about what's hot *now*, so its recency weighting is far
# sharper than the recommender's general-purpose one.
_TRENDING_HALF_LIFE_DAYS = 5.0


def _artist_key(name: str | None) -> str:
    return (name or "").strip().lower()


# ---- Featured spotlight ----------------------------------------------------
#
# The spotlight answers "what should I play next, given what I've just been
# playing?". It is seeded from the user's own recent plays, then filled by
# looking through the library for songs close to those seeds — so a session
# spent on one artist or one mood visibly bends the next spotlight towards it.
#
# It's stored (see FeaturedPlaylist) rather than recomputed per request: the
# build costs upstream lookups, and a banner that reshuffled on every refresh
# would be unreadable. New listening is what makes it change.

# How far back a play still counts as "what I'm listening to now", and how fast
# it fades inside that window — a couple of hours ago outweighs yesterday.
_SEED_DAYS = 3
_SEED_HALF_LIFE_DAYS = 0.5

# How many recent tracks to ask the library for neighbours of. Each is one
# upstream call, so this is the main cost of a rebuild.
_SEED_TRACKS = 6

# Genres to sweep the wider library for, beyond the seeds' own neighbours.
_SEED_GENRES = 2

# How wide the random library sample is. This is what stops the spotlight from
# only ever circling the albums already in the played pool.
_SWEEP_SIZE = 300

# No more than this many tracks by one artist, or a heavy session on a single
# album returns that album back to you as a recommendation.
_MAX_PER_ARTIST = 3

# Below this many genuinely related songs the spotlight isn't worth showing as
# one, and the trending fallback is used instead.
_MIN_TRACKS = 5

# The spotlight holds for at least this long even while you keep listening, so
# it doesn't churn track-by-track mid-session.
_MIN_REBUILD_GAP = dt.timedelta(minutes=15)


async def _recent_play_weight(
    db: AsyncSession, user_id: int, days: int = 14, half_life_days: float = 2.0
) -> dict[str, float]:
    """How much each track has been played lately, the newest counting most.

    This reads the app's own play signals, which carry timestamps, where
    Navidrome only keeps a single last-played date per song.
    """
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    rows = (
        await db.execute(
            select(Signal.track_id, Signal.ts).where(
                Signal.user_id == user_id,
                Signal.ts >= cutoff,
                Signal.type.in_(("play", "play_complete")),
            )
        )
    ).all()
    now = time.time()
    out: dict[str, float] = defaultdict(float)
    for track_id, ts in rows:
        age = ((now - ts.timestamp()) / _DAY) if ts else 0.0
        out[str(track_id)] += 0.5 ** (max(age, 0.0) / half_life_days)
    return out


def _aware(ts: dt.datetime | None) -> dt.datetime | None:
    """Timestamps read back from the database, made safe to compare.

    Postgres returns these timezone-aware; SQLite doesn't, and subtracting one
    kind from the other raises. Everything stored here is UTC either way.
    """
    if ts is not None and ts.tzinfo is None:
        return ts.replace(tzinfo=dt.timezone.utc)
    return ts


async def _last_play_at(db: AsyncSession, user_id: int) -> dt.datetime | None:
    """When this user last played anything — the clock the spotlight runs on."""
    latest = (
        await db.execute(
            select(func.max(Signal.ts)).where(
                Signal.user_id == user_id,
                Signal.type.in_(("play", "play_complete")),
            )
        )
    ).scalar_one_or_none()
    return _aware(latest)


def _weighted(values: dict[str, float]) -> dict[str, float]:
    """Scale a weight map so its strongest entry is 1.0, leaving the different
    kinds of evidence below comparable to each other."""
    top = max(values.values(), default=0.0)
    return {k: v / top for k, v in values.items()} if top > 0 else {}


async def _song(sub: Subsonic, song_id: str) -> dict | None:
    """One track body, or None if the library no longer has it."""
    try:
        return await sub.song(song_id)
    except Exception:
        return None


async def _neighbours(sub: Subsonic, song_id: str) -> list[dict]:
    """Library songs the server considers close to [song_id]. Best-effort: a
    seed the upstream has no similarity data for just contributes nothing."""
    try:
        return await sub.similar_songs(song_id, 30)
    except Exception:
        return []


async def _sweep(sub: Subsonic, genres: list[str]) -> list[dict]:
    """A wide look through the library: a random sample plus the seeds' genres.

    Without this the spotlight could only ever recommend songs from albums the
    user already plays often, which is the opposite of the point.
    """
    jobs = [_safe_call(sub.random_songs(_SWEEP_SIZE))]
    jobs += [_safe_call(sub.songs_by_genre(g, 120)) for g in genres]
    songs: list[dict] = []
    for result in await asyncio.gather(*jobs):
        songs.extend(result)
    return songs


async def _safe_call(coro) -> list[dict]:
    try:
        return await coro
    except Exception:
        return []


async def _build_featured(
    sub: Subsonic,
    db: AsyncSession,
    user_id: int,
    pool: list[dict],
    taste: Taste,
    limit: int,
) -> tuple[list[dict], str] | None:
    """Songs close to what this user has been playing, and a line saying why.

    Returns None when there's nothing recent to work from; the caller falls
    back to the trending spotlight so a new account still gets a banner.
    """
    recent = await _recent_play_weight(
        db, user_id, _SEED_DAYS, _SEED_HALF_LIFE_DAYS
    )
    if not recent:
        return None

    seeds = sorted(recent.items(), key=lambda kv: kv[1], reverse=True)
    seed_ids = {track_id for track_id, _ in seeds}

    # The seeds' own artists and genres, which need the song bodies the signals
    # don't carry. The played pool covers the familiar ones for free; the rest
    # are looked up, because a session spent on something brand new is exactly
    # the case this section exists to follow, and those tracks are the ones
    # least likely to be in the pool.
    by_id = {str(s["id"]): s for s in pool}
    missing = [tid for tid, _ in seeds[:_SEED_TRACKS] if tid not in by_id]
    for song in await asyncio.gather(*(_song(sub, tid) for tid in missing)):
        if song:
            by_id[str(song["id"])] = song

    seed_artists: dict[str, float] = defaultdict(float)
    seed_genres: dict[str, float] = defaultdict(float)
    genre_label: dict[str, str] = {}
    artist_label: dict[str, str] = {}
    for track_id, weight in seeds:
        song = by_id.get(track_id)
        if not song:
            continue
        artist = _artist_key(song.get("artist"))
        if artist:
            seed_artists[artist] += weight
            artist_label[artist] = str(song.get("artist"))
        genre = str(song.get("genre") or "").strip().lower()
        if genre:
            seed_genres[genre] += weight
            genre_label[genre] = str(song["genre"]).strip()
    seed_artists = _weighted(seed_artists)
    seed_genres = _weighted(seed_genres)

    top_genres = [
        genre_label[g]
        for g, _ in sorted(
            seed_genres.items(), key=lambda kv: kv[1], reverse=True
        )[:_SEED_GENRES]
    ]

    # Neighbours of the freshest seeds, and a wide sweep of the library, in
    # parallel — these are all the upstream calls a rebuild makes.
    neighbour_lists, swept = await asyncio.gather(
        asyncio.gather(
            *(_neighbours(sub, tid) for tid, _ in seeds[:_SEED_TRACKS])
        ),
        _sweep(sub, top_genres),
    )

    # How strongly each candidate was pointed at, and by how recent a seed.
    similar_to: dict[str, float] = defaultdict(float)
    candidates: dict[str, dict] = {}
    for (seed_id, weight), neighbours in zip(seeds, neighbour_lists):
        for song in neighbours:
            sid = str(song["id"])
            candidates.setdefault(sid, song)
            similar_to[sid] += weight
    for song in swept + pool:
        candidates.setdefault(str(song["id"]), song)
    similar_to = _weighted(similar_to)

    def relatedness(song: dict) -> float:
        """How close this song is to the session — and nothing else.

        Kept separate from the score so it can gate as well as rank: a song
        with no tie at all to what was just played is not a candidate, however
        appealing it is on its own. Otherwise the wide library sweep, which
        exists to reach past the user's usual albums, would fill the spotlight
        with strangers.
        """
        return (
            # Named as a neighbour of something just played: the strongest
            # evidence there is, and the only one the library computes for us.
            3.0 * similar_to.get(str(song["id"]), 0.0)
            + 2.0 * seed_artists.get(_artist_key(song.get("artist")), 0.0)
            + 1.0
            * seed_genres.get(str(song.get("genre") or "").strip().lower(), 0.0)
        )

    def score(song: dict) -> float:
        return (
            relatedness(song)
            + taste.boost(song)
            # A tie-break only, deliberately small: of two equally related
            # songs, offer the one this user has worn out less.
            + 0.2 / (1.0 + song["playCount"])
        )

    ranked = sorted(
        (
            s
            for s in candidates.values()
            # Just played is not a recommendation.
            if str(s["id"]) not in seed_ids
            and not taste.suppressed(s)
            and relatedness(s) > 0
        ),
        key=score,
        reverse=True,
    )

    picked: list[dict] = []
    per_artist: dict[str, int] = defaultdict(int)
    for song in ranked:
        artist = _artist_key(song.get("artist"))
        if per_artist[artist] >= _MAX_PER_ARTIST:
            continue
        per_artist[artist] += 1
        picked.append(song)
        if len(picked) >= limit:
            break
    # Too thin to be worth showing as "because you played X" — the caller falls
    # back to the trending spotlight rather than putting up three songs.
    if len(picked) < _MIN_TRACKS:
        return None

    lead = max(seed_artists.items(), key=lambda kv: kv[1], default=None)
    subtitle = (
        f"Because you played {artist_label[lead[0]]}"
        if lead and artist_label.get(lead[0])
        else "Based on what you've been playing"
    )
    return picked, subtitle


async def _trending(
    db: AsyncSession, user_id: int, pool: list[dict], taste: Taste, limit: int
) -> list[dict]:
    """The old spotlight — the songs riding highest — kept as the fallback for
    an account with no recent listening to build from."""
    if not pool:
        return []
    recent = await _recent_play_weight(db, user_id)

    def score(song: dict) -> float:
        base = song["playCount"] * (
            0.3 + _recency_weight(song["lastPlayed"], _TRENDING_HALF_LIFE_DAYS)
        )
        return base + 6.0 * recent.get(str(song["id"]), 0.0) + taste.boost(song)

    return sorted(taste.keep(pool), key=score, reverse=True)[:limit]


async def featured(
    sub: Subsonic,
    db: AsyncSession,
    user_id: int,
    pool: list[dict],
    taste: Taste = EMPTY,
    limit: int = 20,
) -> dict | None:
    """The stored spotlight, rebuilt when there's listening it hasn't seen.

    Returned as a playlist rather than a single track because the home screen
    slides through it — one featured song at a time, with the whole set
    openable.
    """
    stored = (
        await db.execute(
            select(FeaturedPlaylist).where(FeaturedPlaylist.user_id == user_id)
        )
    ).scalar_one_or_none()
    now = dt.datetime.now(dt.timezone.utc)
    last_play = await _last_play_at(db, user_id)

    # Rebuild when something has been played since the current spotlight was
    # seeded — but not more than once every _MIN_REBUILD_GAP, so a long session
    # doesn't rewrite the banner under the user between songs.
    seeded_through = _aware(stored.seeded_through) if stored else None
    fresh_listening = stored is not None and (
        last_play is not None
        and (seeded_through is None or last_play > seeded_through)
        and now - _aware(stored.generated_at) >= _MIN_REBUILD_GAP
    )
    if stored is not None and stored.tracks and not fresh_listening:
        return _present_featured(stored)

    built = await _build_featured(sub, db, user_id, pool, taste, limit)
    if built is None:
        tracks = await _trending(db, user_id, pool, taste, limit)
        subtitle = "Riding high today"
    else:
        tracks, subtitle = built
    if not tracks:
        return _present_featured(stored) if stored and stored.tracks else None

    if stored is None:
        stored = FeaturedPlaylist(user_id=user_id)
        db.add(stored)
    stored.tracks = tracks
    stored.subtitle = subtitle
    stored.generated_at = now
    stored.seeded_through = last_play
    await db.commit()
    return _present_featured(stored)


def _present_featured(stored: FeaturedPlaylist) -> dict:
    return {
        "key": "featured",
        "title": "Featured",
        "subtitle": stored.subtitle or "Made for you",
        "tracks": stored.tracks,
    }


# ---- Albums for you --------------------------------------------------------


async def albums_for_you(
    sub: Subsonic, pool: list[dict], taste: Taste = EMPTY, limit: int = 12
) -> list[dict]:
    """Albums worth a listen: strong artist fit, not already worn out.

    Ranked by how much the user likes the artist, then penalised by how much of
    the album they've already played — a suggestion should point somewhere.
    """
    plays: dict[str, int] = defaultdict(int)
    for song in pool:
        if song.get("albumId"):
            plays[str(song["albumId"])] += song["playCount"]

    loved: dict[str, float] = defaultdict(float)
    for song in pool:
        artist = _artist_key(song.get("artist"))
        if artist:
            loved[artist] = max(
                loved[artist], song["playCount"] + taste.boost(song)
            )

    try:
        candidates = await sub.album_list2("alphabeticalByName", size=400)
    except Exception:
        return []

    scored = []
    for album in candidates:
        artist = _artist_key(album.get("artist"))
        affinity = loved.get(artist, 0.0)
        if affinity <= 0:
            continue
        played = plays.get(str(album.get("id")), 0)
        # Diminishing returns on albums already played through.
        scored.append((affinity / (1.0 + played), album))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [a for _, a in scored[:limit]]


# ---- Mood rows -------------------------------------------------------------


def _top_genres(pool: list[dict], taste: Taste, limit: int = 3) -> list[str]:
    """The genres this user actually listens to, best first."""
    weight: dict[str, float] = defaultdict(float)
    label: dict[str, str] = {}
    for song in pool:
        genre = song.get("genre")
        if not genre:
            continue
        key = str(genre).strip().lower()
        if not key:
            continue
        label[key] = str(genre).strip()
        weight[key] += song["playCount"] + taste.boost(song)
    ranked = sorted(weight.items(), key=lambda kv: kv[1], reverse=True)
    return [label[k] for k, _ in ranked[:limit]]


async def _mood_row(
    sub: Subsonic, genre: str, playlists: list[dict], taste: Taste
) -> dict | None:
    """One mood row: a mix of that genre, plus matching playlists and albums.

    Mixing card types in a single row is the point — a mood is a place you
    browse, not just another track list.
    """
    try:
        songs = taste.keep(await sub.songs_by_genre(genre, 120))
    except Exception:
        return None
    if not songs:
        return None

    items: list[dict] = [
        {
            "type": "mix",
            "id": f"genre-{genre.lower()}",
            "title": f"{genre} Mix",
            "subtitle": f"{len(songs)} songs",
            "coverArt": songs[0].get("coverArt"),
            "tracks": songs[:40],
        }
    ]

    # The user's own playlists that name this genre — "French Classical" under
    # Classical, and so on.
    needle = genre.lower()
    for p in playlists:
        if needle in str(p.get("name", "")).lower():
            items.append(
                {
                    "type": "playlist",
                    "id": str(p.get("id")),
                    "title": str(p.get("name", "Playlist")),
                    "subtitle": f"{p.get('songCount', 0)} songs",
                    "coverArt": p.get("coverArt"),
                }
            )

    # Albums that are mostly this genre, by how much of them we saw.
    albums: dict[str, dict] = {}
    counts: dict[str, int] = defaultdict(int)
    for song in songs:
        aid = song.get("albumId")
        if not aid:
            continue
        aid = str(aid)
        counts[aid] += 1
        albums.setdefault(
            aid,
            {
                "type": "album",
                "id": aid,
                "title": song.get("album") or "Album",
                "subtitle": song.get("artist") or "",
                "coverArt": song.get("coverArt"),
            },
        )
    for aid, _ in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:8]:
        items.append(albums[aid])

    return {"genre": genre, "title": genre, "items": items}


async def mood_rows(
    sub: Subsonic,
    pool: list[dict],
    playlists: list[dict],
    taste: Taste = EMPTY,
    limit: int = 3,
) -> list[dict]:
    rows = []
    for genre in _top_genres(pool, taste, limit):
        row = await _mood_row(sub, genre, playlists, taste)
        if row:
            rows.append(row)
    return rows
