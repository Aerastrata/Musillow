"""Rotating discovery mixes (the Daily Mixes and the Weekly).

These used to be a view over the user's *most-played* tracks — maximally
familiar, and identical every time you looked. They now do the opposite job:
surface songs you haven't heard, or have heard exactly once, chosen for their
relation to what you already like.

Three rules govern rotation, and they're the reason a mix has to be stored
rather than recomputed:

* A mix rotates only once its window has passed **and** you've actually played
  something from it. An untouched mix waits — replacing something you never
  heard would defeat the point of offering it.
* Tracks you didn't save are rotated out and put on a cooldown, so the next mix
  is genuinely new rather than a reshuffle of the same pool.
* Saved tracks are exempt from that cooldown. Saving one is a request to keep
  it, and starring is the gesture the app already has.
"""
import datetime as dt
import random

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import lb_discover
from .models import Mix, MixSeen, Signal
from .subsonic import Subsonic
from .taste import Taste

_DOW = [
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
]

# A surfaced-but-unsaved track stays out of mixes for this long.
_COOLDOWN_DAYS = 60

# Tracks per mix, and how many daily mixes we'll build when the pool allows.
_MIX_SIZE = 25
_MAX_DAILY = 7

# How wide a net to cast when sampling the library for unfamiliar songs.
_SAMPLE_SIZE = 500
_NEW_ALBUMS = 15

# A song counts as unfamiliar at or below this play count — "never heard, or
# heard once and not returned to".
_UNFAMILIAR_PLAYS = 1


def _now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _artist_key(name: str | None) -> str:
    return (name or "").strip().lower()


def _ids(mix: Mix) -> list[str]:
    return [str(t.get("id")) for t in (mix.tracks or []) if t.get("id")]


# ---- Candidate pool --------------------------------------------------------


async def _unfamiliar_pool(sub: Subsonic) -> list[dict]:
    """Library songs the user hasn't really heard yet.

    Sampled rather than enumerated: `getRandomSongs` is one cheap call that
    reaches the whole library (including things never played, which the
    play-count-ordered album lists never surface), and recently-added albums are
    folded in so new arrivals always qualify as candidates.
    """
    songs: dict[str, dict] = {}
    for s in await sub.random_songs(_SAMPLE_SIZE):
        songs[s["id"]] = s
    try:
        for album in await sub.album_list2("newest", size=_NEW_ALBUMS):
            for s in await sub.album_songs(str(album["id"])):
                songs[s["id"]] = s
    except Exception:
        # Recently-added is a bonus; a failure just narrows the pool.
        pass
    return [s for s in songs.values() if s["playCount"] <= _UNFAMILIAR_PLAYS]


async def _related_artists(sub: Subsonic, pool: list[dict]) -> set[str]:
    """Artists ListenBrainz considers close to the user's favourites.

    Token-less and best-effort — when it's unavailable the mix still works,
    just leaning entirely on the user's own artists and genres.
    """
    try:
        found = await lb_discover.discover(sub, pool, 60)
    except Exception:
        return set()
    return {_artist_key(s.get("artist")) for s in (found or [])}


def _affinities(played: list[dict], taste: Taste) -> tuple[set[str], set[str]]:
    """The artists and genres the user demonstrably likes."""
    ranked = sorted(
        played, key=lambda s: s["playCount"] + taste.boost(s), reverse=True
    )[:80]
    artists = {_artist_key(s.get("artist")) for s in ranked if s.get("artist")}
    genres = {
        str(s["genre"]).lower() for s in ranked if s.get("genre")
    }
    return artists - {""}, genres


def _relatedness(
    song: dict,
    taste: Taste,
    loved_artists: set[str],
    loved_genres: set[str],
    similar_artists: set[str],
) -> float:
    """How well an unfamiliar song fits what this user already likes."""
    artist = _artist_key(song.get("artist"))
    score = 2.0 * taste.artist_score(song)
    if artist in loved_artists:
        score += 2.0
    elif artist in similar_artists:
        score += 1.5
    if song.get("genre") and str(song["genre"]).lower() in loved_genres:
        score += 1.0
    # A song heard once and not returned to is a slightly safer bet than one
    # never touched at all — it got past the skip.
    if song["playCount"] == 1:
        score += 0.4
    return score


# ---- Stored state ----------------------------------------------------------


async def _seen_ids(db: AsyncSession, user_id: int) -> set[str]:
    """Tracks still inside their post-rotation cooldown."""
    cutoff = _now() - dt.timedelta(days=_COOLDOWN_DAYS)
    rows = await db.execute(
        select(MixSeen.track_id).where(
            MixSeen.user_id == user_id, MixSeen.ts >= cutoff
        )
    )
    return {r[0] for r in rows.all()}


async def _mark_seen(db: AsyncSession, user_id: int, track_ids: list[str]) -> None:
    """Start (or restart) the cooldown for tracks that were rotated out."""
    if not track_ids:
        return
    existing = {
        r[0]
        for r in (
            await db.execute(
                select(MixSeen.track_id).where(
                    MixSeen.user_id == user_id, MixSeen.track_id.in_(track_ids)
                )
            )
        ).all()
    }
    now = _now()
    for track_id in track_ids:
        if track_id in existing:
            await db.execute(
                MixSeen.__table__.update()
                .where(MixSeen.user_id == user_id, MixSeen.track_id == track_id)
                .values(ts=now)
            )
        else:
            db.add(MixSeen(user_id=user_id, track_id=track_id, ts=now))


async def _played_since(
    db: AsyncSession, user_id: int, track_ids: list[str], since: dt.datetime
) -> bool:
    """Whether the user has played anything from this mix since it was made.

    Read straight off the taste signals the app already sends, so nothing new
    has to be reported from the client for rotation to work.
    """
    if not track_ids:
        return False
    row = await db.execute(
        select(Signal.id)
        .where(
            Signal.user_id == user_id,
            Signal.track_id.in_(track_ids),
            Signal.type.in_(("play", "play_complete")),
            Signal.ts >= since,
        )
        .limit(1)
    )
    return row.first() is not None


# ---- Generation ------------------------------------------------------------


def _slice_mixes(
    candidates: list[dict], count: int, size: int, seed: int
) -> list[list[dict]]:
    """Cut the ranked candidates into [count] disjoint mixes.

    Dealt round-robin rather than sliced in blocks so every mix gets a share of
    the strongest matches instead of the first mix taking them all.
    """
    if not candidates:
        return []
    count = max(1, min(count, max(1, len(candidates) // max(size // 3, 1))))
    buckets: list[list[dict]] = [[] for _ in range(count)]
    for i, song in enumerate(candidates):
        bucket = buckets[i % count]
        if len(bucket) < size:
            bucket.append(song)
    rnd = random.Random(seed)
    for bucket in buckets:
        rnd.shuffle(bucket)
    return [b for b in buckets if b]


async def _build(
    sub: Subsonic,
    db: AsyncSession,
    user_id: int,
    taste: Taste,
    played_pool: list[dict],
    exclude: set[str],
) -> tuple[list[list[dict]], list[dict]]:
    """Rank unfamiliar songs by fit and deal them into daily + weekly mixes."""
    pool = await _unfamiliar_pool(sub)
    seen = await _seen_ids(db, user_id)
    starred = {s["id"] for s in await sub.starred_songs()}

    loved_artists, loved_genres = _affinities(played_pool, taste)
    similar = await _related_artists(sub, played_pool)

    candidates = [
        s
        for s in pool
        if s["id"] not in seen
        and s["id"] not in exclude
        # Already saved means already yours — a mix is for things you haven't
        # decided about yet.
        and s["id"] not in starred
        and not taste.suppressed(s)
    ]
    candidates.sort(
        key=lambda s: _relatedness(
            s, taste, loved_artists, loved_genres, similar
        ),
        reverse=True,
    )
    # Keep the pool honest: only the genuinely well-matched half is worth
    # offering, or a thin library starts serving random noise as "for you".
    top = candidates[: _MIX_SIZE * (_MAX_DAILY + 1)]
    seed = int(_now().timestamp() // 86400)
    dealt = _slice_mixes(top, _MAX_DAILY + 1, _MIX_SIZE, seed)
    if not dealt:
        return [], []
    return dealt[:-1] if len(dealt) > 1 else dealt, (
        dealt[-1] if len(dealt) > 1 else []
    )


def _window(key: str) -> dt.timedelta:
    """How long a mix holds before it's *eligible* to rotate."""
    return dt.timedelta(days=7)


async def ensure(
    sub: Subsonic,
    db: AsyncSession,
    user_id: int,
    taste: Taste,
    played_pool: list[dict],
) -> list[dict]:
    """Return this user's current mixes, rotating any that are due.

    Due means: the window has passed *and* they've played something from it.
    """
    stored = (
        await db.execute(select(Mix).where(Mix.user_id == user_id))
    ).scalars().all()
    by_key = {m.key: m for m in stored}
    now = _now()

    # Which stored mixes are ready to be replaced?
    rotating: list[Mix] = []
    for mix in stored:
        if now < mix.rotates_after:
            continue
        if await _played_since(db, user_id, _ids(mix), mix.generated_at):
            rotating.append(mix)

    keys = [f"daily-{d.lower()}" for d in _DOW] + ["weekly"]
    missing = [k for k in keys if k not in by_key]

    if missing or rotating:
        # Everything currently held onto stays out of the new draw.
        keep_ids = {
            tid for m in stored if m not in rotating for tid in _ids(m)
        }
        # The tracks on their way out are excluded from the draw as well —
        # otherwise a rotating mix can be handed back the very songs it is
        # rotating out, and "new" means nothing.
        outgoing = {tid for m in rotating for tid in _ids(m)}
        daily, weekly = await _build(
            sub, db, user_id, taste, played_pool, keep_ids | outgoing
        )
        fresh: dict[str, list[dict]] = {}
        for i, key in enumerate(k for k in keys if k != "weekly"):
            if i < len(daily):
                fresh[key] = daily[i]
        if weekly:
            fresh["weekly"] = weekly

        saved = {s["id"] for s in await sub.starred_songs()} if rotating else set()
        for mix in rotating:
            replacement = fresh.pop(mix.key, None)
            if replacement is None:
                # Nothing new to offer — hold the mix rather than empty it, and
                # leave its tracks off cooldown since they're still on show.
                continue
            await _mark_seen(
                db, user_id, [t for t in _ids(mix) if t not in saved]
            )
            mix.tracks = replacement
            mix.generated_at = now
            mix.rotates_after = now + _window(mix.key)

        for key, songs in fresh.items():
            if key in by_key:
                continue
            db.add(
                Mix(
                    user_id=user_id,
                    key=key,
                    title=_title(key),
                    subtitle=_subtitle(key),
                    tracks=songs,
                    generated_at=now,
                    rotates_after=now + _window(key),
                )
            )
        await db.commit()
        stored = (
            await db.execute(select(Mix).where(Mix.user_id == user_id))
        ).scalars().all()

    return _present(stored)


def _title(key: str) -> str:
    if key == "weekly":
        return "Weekly Discovery"
    return f"{key.removeprefix('daily-').capitalize()} Mix"


def _subtitle(key: str) -> str:
    if key == "weekly":
        return "New to you, all week"
    return "Songs you haven't heard yet"


def _present(stored: list[Mix]) -> list[dict]:
    """Order the stored mixes for the home screen: today's first, then the rest
    of the week, then the weekly."""
    today = _DOW[_now().weekday()].lower()
    out = []
    for mix in stored:
        if not mix.tracks:
            continue
        out.append(
            {
                "key": mix.key,
                "title": mix.title,
                "subtitle": (
                    "Made for you today"
                    if mix.key == f"daily-{today}"
                    else mix.subtitle
                ),
                "tracks": mix.tracks,
            }
        )
    order = [f"daily-{d.lower()}" for d in _DOW]
    start = order.index(f"daily-{today}")
    rank = {k: i for i, k in enumerate(order[start:] + order[:start])}
    rank["weekly"] = len(order)
    out.sort(key=lambda m: rank.get(m["key"], 99))
    return out
