from fastapi import APIRouter, Depends
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..deps import get_current_user
from ..models import Signal, User
from ..schemas import SignalIn

# Signal weights from the spec's Taste Signal Pipeline.
WEIGHTS = {
    "like": 1.0,
    "playlist_add": 0.8,
    "play_complete": 0.5,
    "play": 0.4,
    "skip": -0.6,
    "expire": -0.2,
}

router = APIRouter(prefix="/signals", tags=["signals"])


@router.post("")
async def add_signal(
    body: SignalIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    weight = WEIGHTS.get(body.type, 0.0)
    db.add(
        Signal(
            user_id=user.id, type=body.type, track_id=body.trackId, weight=weight
        )
    )
    await db.commit()
    return {"ok": True, "weight": weight}


@router.get("/recent")
async def recent(
    limit: int = 100,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rows = (
        await db.execute(
            select(Signal)
            .where(Signal.user_id == user.id)
            .order_by(desc(Signal.ts))
            .limit(limit)
        )
    ).scalars().all()
    return {
        "signals": [
            {
                "ts": r.ts.isoformat() if r.ts else None,
                "type": r.type,
                "trackId": r.track_id,
                "weight": r.weight,
            }
            for r in rows
        ]
    }
