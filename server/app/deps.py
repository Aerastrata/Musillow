"""Shared FastAPI dependencies."""
from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .db import get_db
from .models import User
from .security import decode_token


async def _user_for_token(token: str, db: AsyncSession) -> User:
    try:
        payload = decode_token(token)
        user_id = int(payload["sub"])
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = (
        await db.execute(select(User).where(User.id == user_id))
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")
    return user


async def get_current_user(
    authorization: str | None = Header(default=None),
    db: AsyncSession = Depends(get_db),
) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    return await _user_for_token(authorization.split(" ", 1)[1], db)


async def get_current_user_media(
    authorization: str | None = Header(default=None),
    token: str | None = None,
    db: AsyncSession = Depends(get_db),
) -> User:
    """Auth for media (audio/cover) requests. Accepts the usual bearer header
    or a `?token=` query param, since audio players and image loaders can't
    always attach custom headers."""
    if authorization and authorization.startswith("Bearer "):
        return await _user_for_token(authorization.split(" ", 1)[1], db)
    if token:
        return await _user_for_token(token, db)
    raise HTTPException(status_code=401, detail="Missing token")
