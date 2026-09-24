"""The home screen, composed server-side.

Home used to make about nine requests from the phone — random songs, quick
picks, generated playlists, then a full track fetch per playlist just to get its
cover art — and each of those independently rebuilt the same expensive
"frequently played" pool upstream. Adding rows to that would have made the page
slower with every feature.

This assembles the whole page in one response instead: the library pool and the
user's taste are computed once and shared by every section, and the sections run
concurrently. Any one of them failing degrades to an empty row rather than
taking the page down.
"""
import asyncio

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from .. import curation, explore, mixes, recommend
from .. import taste as taste_mod
from ..abs import AbsError
from ..db import get_db
from ..http import client as http_client
from ..deps import get_current_user
from ..models import User
from ..services import abs_for, has_connector, navidrome_for

router = APIRouter(tags=["home"])


async def _safe(coro, default):
    """Run a section, falling back to [default] if it fails. One dead row
    shouldn't blank the home screen."""
    try:
        return await coro
    except Exception:
        return default


async def _continue_listening(user: User, db: AsyncSession) -> list[dict]:
    if not await has_connector(user.id, "abs", db):
        return []
    try:
        client = await abs_for(user.id, db)
        return await client.in_progress(10)
    except (AbsError, Exception):
        return []


@router.get("/home")
async def home(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    # Music is optional here: an account with only Audiobookshelf set up should
    # still get a home screen with its audiobooks on it, not a 400.
    try:
        sub = await navidrome_for(user.id, db)
    except HTTPException:
        return {
            "greetingName": user.username,
            "featured": None,
            "quickPicks": [],
            "mixes": [],
            "albumsForYou": [],
            "moodRows": [],
            "forgottenFaves": [],
            "newReleases": [],
            "jumpBackIn": [],
            "artists": [],
            "continueListening": await _continue_listening(user, db),
            "playlists": [],
        }

    # The one expensive read, shared by everything that needs it.
    pool = await _safe(recommend._played_pool(sub), [])
    taste = await _safe(taste_mod.load(db, user.id, pool), taste_mod.EMPTY)

    # Mixes touch the database, so they're awaited on their own; the rest are
    # independent upstream reads and run together.
    mix_rows = await _safe(mixes.ensure(sub, db, user.id, taste, pool), [])

    # The spotlight reads the signals table and writes back the playlist it
    # builds, so it's awaited alongside mixes rather than in the upstream-only
    # gather. It only does upstream work on the loads where there's been new
    # listening to rebuild from.
    spotlight = await _safe(
        curation.featured(sub, db, user.id, pool, taste), None
    )

    (
        quick,
        recent,
        artists,
        playlists,
        books,
        forgotten,
        albums_for_you,
    ) = await asyncio.gather(
        _safe(recommend.quick_picks(sub, taste, pool), {"rows": []}),
        _safe(sub.album_list2("recent", size=12), []),
        _safe(explore.top_artists(sub, pool, 12), []),
        _safe(sub.playlists(), []),
        _continue_listening(user, db),
        _safe(recommend.playlist(sub, "forgotten", 30, taste), []),
        _safe(curation.albums_for_you(sub, pool, taste), []),
    )

    # Mood rows and new releases both need results from above, so they follow.
    moods, releases = await asyncio.gather(
        _safe(curation.mood_rows(sub, pool, playlists, taste), []),
        _safe(
            explore.new_releases(
                http_client(), [a["name"] for a in artists[:5]], 20
            ),
            [],
        ),
    )

    return {
        "greetingName": user.username,
        # A playlist, not a single track: the home screen slides through it.
        "featured": spotlight,
        "quickPicks": quick.get("rows", []),
        "mixes": mix_rows,
        "albumsForYou": albums_for_you,
        "moodRows": moods,
        "forgottenFaves": forgotten or [],
        "newReleases": releases,
        "jumpBackIn": recent,
        "artists": artists,
        "continueListening": books,
        "playlists": playlists,
    }
