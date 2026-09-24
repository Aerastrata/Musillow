"""Helpers that build external clients from a user's stored connectors."""
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import http
from .abs import Abs
from .models import Connector
from .security import decrypt
from .subsonic import Subsonic


async def _connector(user_id: int, kind: str, db: AsyncSession) -> Connector | None:
    return (
        await db.execute(
            select(Connector).where(
                Connector.user_id == user_id, Connector.kind == kind
            )
        )
    ).scalar_one_or_none()


async def navidrome_for(user_id: int, db: AsyncSession) -> Subsonic:
    connector = await _connector(user_id, "navidrome", db)
    if connector is None:
        raise HTTPException(
            status_code=400,
            detail="No Navidrome connector configured for this account.",
        )
    return Subsonic(
        connector.base_url,
        connector.username,
        decrypt(connector.secret_enc),
        http.client(),
    )


async def abs_for(user_id: int, db: AsyncSession) -> Abs:
    connector = await _connector(user_id, "abs", db)
    if connector is None:
        raise HTTPException(
            status_code=400,
            detail="No Audiobookshelf connector configured for this account.",
        )
    return Abs(
        connector.base_url,
        connector.username,
        decrypt(connector.secret_enc),
        http.client(),
    )


async def has_connector(user_id: int, kind: str, db: AsyncSession) -> bool:
    return await _connector(user_id, kind, db) is not None
