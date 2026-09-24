from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import abs as abs_client
from .. import http
from ..db import get_db
from ..deps import get_current_user
from ..models import Connector, User
from ..schemas import ConnectorIn, ConnectorOut
from ..security import encrypt
from ..subsonic import Subsonic, SubsonicError

router = APIRouter(prefix="/me/connectors", tags=["connectors"])

_KINDS = {"navidrome", "abs"}


@router.get("", response_model=list[ConnectorOut])
async def list_connectors(
    user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)
):
    rows = (
        await db.execute(select(Connector).where(Connector.user_id == user.id))
    ).scalars().all()
    return [
        ConnectorOut(kind=c.kind, baseUrl=c.base_url, username=c.username)
        for c in rows
    ]


@router.put("", response_model=ConnectorOut)
async def upsert_connector(
    body: ConnectorIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    kind = body.kind.lower()
    if kind not in _KINDS:
        raise HTTPException(status_code=400, detail="Unknown connector kind")

    base_url = body.baseUrl.rstrip("/")

    # Validate credentials before storing them, so a typo fails here rather
    # than silently breaking every later request.
    if kind == "navidrome":
        try:
            await Subsonic(base_url, body.username, body.secret, http.client()).ping()
        except SubsonicError as e:
            raise HTTPException(
                status_code=400, detail=f"Navidrome rejected credentials: {e}"
            )
        except Exception:
            raise HTTPException(status_code=400, detail="Could not reach Navidrome")
    elif kind == "abs":
        try:
            await abs_client.login(
                base_url, body.username, body.secret, http.client()
            )
        except abs_client.AbsError as e:
            raise HTTPException(status_code=400, detail=str(e))
        except Exception:
            raise HTTPException(
                status_code=400, detail="Could not reach Audiobookshelf"
            )

    connector = (
        await db.execute(
            select(Connector).where(
                Connector.user_id == user.id, Connector.kind == kind
            )
        )
    ).scalar_one_or_none()
    if connector is None:
        connector = Connector(user_id=user.id, kind=kind)
        db.add(connector)
    elif kind == "abs":
        # Retire the token minted from the credentials we're replacing.
        abs_client.forget(connector.base_url, connector.username)
    connector.base_url = base_url
    connector.username = body.username
    connector.secret_enc = encrypt(body.secret)
    await db.commit()
    return ConnectorOut(kind=kind, baseUrl=base_url, username=body.username)


@router.delete("/{kind}")
async def delete_connector(
    kind: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    connector = (
        await db.execute(
            select(Connector).where(
                Connector.user_id == user.id, Connector.kind == kind.lower()
            )
        )
    ).scalar_one_or_none()
    if connector:
        if connector.kind == "abs":
            abs_client.forget(connector.base_url, connector.username)
        await db.delete(connector)
        await db.commit()
    return {"ok": True}
