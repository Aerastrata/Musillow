"""Keep a rotating Charts folder full of the current top-20 (per chart).

Each chart track's *full* audio is downloaded (via Soulseek/slskd) into the
Charts folder so it's playable, capped to the current chart — tracks that drop
off the chart are deleted, unless the user "kept" them (which moves them into
the main library so they survive rotation).

The sync is heavy (a download per new chart entry), so it runs at most every few
hours, in the background, and only downloads entries it doesn't already have.
"""
import asyncio
import logging
import os
import re
import time

from sqlalchemy import select

from . import explore, fulfill
from .config import settings
from .db import SessionLocal
from .http import client as http_client
from .models import ChartTrack, User
from .services import navidrome_for

log = logging.getLogger("musillow.charts")

_CHARTS = {"au": "au", "worldwide": "us"}  # our name → Apple RSS country
_last_sync = 0.0
_SYNC_INTERVAL = 6 * 3600.0
_lock = asyncio.Lock()
_sem = asyncio.Semaphore(4)  # cap concurrent Soulseek downloads


def _norm(s: str | None) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", (s or "").lower()))


def _key(artist: str, title: str) -> str:
    return f"{_norm(artist)}|{_norm(title)}"


async def _rescan() -> None:
    async with SessionLocal() as db:
        for u in (await db.execute(select(User))).scalars().all():
            try:
                sub = await navidrome_for(u.id, db)
                await sub.start_scan()
                return
            except Exception:
                continue


async def maybe_sync(force: bool = False, top_n: int = 20) -> None:
    """Throttled entry point (safe to call on every home load)."""
    global _last_sync
    if not force and (time.time() - _last_sync) < _SYNC_INTERVAL:
        return
    if _lock.locked():
        return
    async with _lock:
        _last_sync = time.time()
        try:
            await _sync(top_n)
        except Exception:
            log.exception("charts sync failed")


async def _download_one(chart: str, artist: str, title: str) -> bool:
    """Ensure a chart track is downloaded into the Charts folder (its own DB
    session so these can run concurrently)."""
    async with SessionLocal() as db:
        row = (
            await db.execute(
                select(ChartTrack).where(
                    ChartTrack.chart == chart,
                    ChartTrack.artist == artist,
                    ChartTrack.title == title,
                )
            )
        ).scalar_one_or_none()
        if row and row.path:
            return False
        if row is None:
            row = ChartTrack(chart=chart, artist=artist, title=title)
            db.add(row)
            await db.commit()
            await db.refresh(row)
        rid = row.id
    async with _sem:
        path = await fulfill.download_track_to(
            http_client(), artist, title, settings.charts_dir
        )
    if not path:
        return False
    async with SessionLocal() as db:
        row = (
            await db.execute(select(ChartTrack).where(ChartTrack.id == rid))
        ).scalar_one_or_none()
        if row:
            row.path = path
            await db.commit()
    return True


async def _sync(top_n: int) -> None:
    client = http_client()
    tasks = []
    chart_keys: dict[str, set] = {}
    for chart, country in _CHARTS.items():
        tracks = (await explore.charts(client, country, top_n))[:top_n]
        chart_keys[chart] = {_key(t["artist"], t["title"]) for t in tracks}
        for t in tracks:
            tasks.append(_download_one(chart, t["artist"], t["title"]))
    # Download the whole top-20 (per chart) in parallel, capped by the semaphore.
    results = await asyncio.gather(*tasks, return_exceptions=True)
    changed = any(r is True for r in results if not isinstance(r, Exception))
    # Rotation: drop non-kept tracks that fell off each chart.
    for chart, current in chart_keys.items():
        async with SessionLocal() as db:
            rows = (
                await db.execute(select(ChartTrack).where(ChartTrack.chart == chart))
            ).scalars().all()
            for r in rows:
                if r.kept or _key(r.artist, r.title) in current:
                    continue
                if r.path and os.path.exists(r.path):
                    try:
                        os.remove(r.path)
                    except Exception:
                        pass
                await db.delete(r)
                changed = True
            await db.commit()
    if changed:
        await _rescan()


async def owned_map() -> dict[str, bool]:
    """artist|title → kept?, for every downloaded chart track (to flag the app)."""
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(ChartTrack).where(ChartTrack.path.is_not(None))
            )
        ).scalars().all()
    return {_key(r.artist, r.title): r.kept for r in rows}


async def keep(artist: str, title: str) -> bool:
    """Promote a chart track into the main library so rotation won't delete it.
    A track can be in several charts (e.g. AU + worldwide) — move the file once
    and mark every matching row kept."""
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(ChartTrack).where(
                    ChartTrack.artist == artist, ChartTrack.title == title
                )
            )
        ).scalars().all()
        if not rows:
            return False
        moved: str | None = None
        for r in rows:
            if r.path and os.path.exists(r.path):
                try:
                    moved = fulfill._move_to(r.path, settings.library_dir)
                except Exception:
                    moved = None
                break
        for r in rows:
            if moved:
                r.path = moved
            r.kept = True
        await db.commit()
    await _rescan()
    return True
