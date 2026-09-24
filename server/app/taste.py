"""Per-user taste, learned from Musillow's own signals.

The app has always sent taste signals (like / playlist_add / play_complete /
play / skip) and the backend has always stored them — but nothing ever read them
back, so they had no effect on what anyone was recommended. This turns them into
two usable things:

* a decayed score per track, so recent likes count more than old ones, and
* an affinity per artist derived from those tracks, so liking one song nudges
  the rest of that artist rather than only the exact track.

Deliberately self-contained: no ListenBrainz account, no API key, nothing to
sign up for. Two accounts pointed at the same library still diverge, because
this is learned from what each person actually did in the app.
"""
import time

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import Signal

_DAY = 86400.0

# How quickly a signal stops mattering. Long enough that a week of not opening
# the app doesn't reset your taste, short enough to follow a change in it.
_HALF_LIFE_DAYS = 45.0

# A track this disliked is dropped from generated playlists outright — roughly
# two recent skips, i.e. a deliberate "not this one".
_SUPPRESS_AT = -1.0

# How hard learned taste pushes against raw play counts. Track evidence is
# direct so it outweighs the artist generalisation.
_TRACK_PULL = 4.0
_ARTIST_PULL = 2.0


class Taste:
    """A user's learned preferences, ready to score songs with."""

    def __init__(self, tracks: dict[str, float], artists: dict[str, float]):
        self.tracks = tracks
        self.artists = artists

    def __bool__(self) -> bool:
        return bool(self.tracks)

    def track_score(self, song: dict) -> float:
        return self.tracks.get(str(song.get("id")), 0.0)

    def artist_score(self, song: dict) -> float:
        return self.artists.get(_artist_key(song.get("artist")), 0.0)

    def boost(self, song: dict) -> float:
        """Additive adjustment to a song's library score."""
        return (
            _TRACK_PULL * self.track_score(song)
            + _ARTIST_PULL * self.artist_score(song)
        )

    def suppressed(self, song: dict) -> bool:
        """True for songs the user has clearly pushed away."""
        return self.track_score(song) <= _SUPPRESS_AT

    def keep(self, songs: list[dict]) -> list[dict]:
        return [s for s in songs if not self.suppressed(s)]


def _artist_key(name: str | None) -> str:
    return (name or "").strip().lower()


EMPTY = Taste({}, {})


async def load(db: AsyncSession, user_id: int, pool: list[dict] | None = None) -> Taste:
    """Build a user's taste from their stored signals.

    [pool] is the library songs already fetched by the caller; it supplies the
    track → artist mapping the signals themselves don't carry.
    """
    rows = (
        await db.execute(
            select(Signal.track_id, Signal.weight, Signal.ts).where(
                Signal.user_id == user_id
            )
        )
    ).all()
    if not rows:
        return EMPTY

    now = time.time()
    tracks: dict[str, float] = {}
    for track_id, weight, ts in rows:
        if not weight:
            continue
        age_days = ((now - ts.timestamp()) / _DAY) if ts else 0.0
        # A true half-life: a signal is worth half as much every
        # _HALF_LIFE_DAYS, so old enthusiasm fades instead of ruling forever.
        decay = 0.5 ** (max(age_days, 0.0) / _HALF_LIFE_DAYS)
        tracks[str(track_id)] = tracks.get(str(track_id), 0.0) + weight * decay

    # Generalise to artists via the library pool, averaging so a user's most
    # -played artist isn't automatically their most-liked one.
    artists: dict[str, float] = {}
    if pool:
        totals: dict[str, list[float]] = {}
        for song in pool:
            score = tracks.get(str(song.get("id")))
            if score is None:
                continue
            totals.setdefault(_artist_key(song.get("artist")), []).append(score)
        artists = {
            name: sum(scores) / len(scores)
            for name, scores in totals.items()
            if name and scores
        }
    return Taste(tracks, artists)
