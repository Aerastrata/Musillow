import datetime as dt
import os

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..db import get_db
from ..images import sniff_image_mime
from ..deps import get_current_user, get_current_user_media
from ..models import User
from ..schemas import LoginIn, RegisterIn, TokenOut, UpdateMeIn, UserOut
from ..security import create_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


def _user_out(user: User) -> UserOut:
    """Serialise a user, including whether a profile picture is set. The
    version is the picture's last-write time, so clients can cache the image
    URL and still see a replacement immediately."""
    return UserOut(
        id=user.id,
        username=user.username,
        email=user.email,
        avatar=user.avatar_mime is not None,
        avatarVersion=(
            int(user.avatar_updated_at.timestamp()) if user.avatar_updated_at else 0
        ),
    )


@router.post("/register", response_model=TokenOut)
async def register(body: RegisterIn, db: AsyncSession = Depends(get_db)):
    if not body.username or not body.password:
        raise HTTPException(status_code=400, detail="Username and password required")
    existing = (
        await db.execute(
            select(User).where(
                func.lower(User.username) == body.username.lower()
            )
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="Username already taken")
    user = User(
        username=body.username,
        email=body.email,
        password_hash=hash_password(body.password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return TokenOut(access_token=create_token(user.id))


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    user = (
        await db.execute(
            select(User).where(
                func.lower(User.username) == body.username.lower()
            )
        )
    ).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return TokenOut(access_token=create_token(user.id))


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)):
    return _user_out(user)


@router.patch("/me", response_model=UserOut)
async def update_me(
    body: UpdateMeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.username and body.username != user.username:
        clash = (
            await db.execute(
                select(User).where(
                    func.lower(User.username) == body.username.lower(),
                    User.id != user.id,
                )
            )
        ).scalar_one_or_none()
        if clash:
            raise HTTPException(status_code=409, detail="Username already taken")
        user.username = body.username
    if body.email is not None:
        user.email = body.email or None
    if body.password:
        user.password_hash = hash_password(body.password)
    await db.commit()
    await db.refresh(user)
    return _user_out(user)


# ---- Profile picture -------------------------------------------------------

_MAX_AVATAR_BYTES = 4 * 1024 * 1024  # 4 MB


def _avatar_path(user_id: int) -> str:
    """On-disk location of a user's profile picture."""
    return os.path.join(settings.avatars_dir, str(int(user_id)))


@router.put("/me/avatar", response_model=UserOut)
async def upload_avatar(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Replace the account's profile picture with an uploaded image."""
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image")
    if len(data) > _MAX_AVATAR_BYTES:
        raise HTTPException(status_code=413, detail="Image too large (max 4 MB)")
    # Identified from the bytes, not the declared Content-Type — see images.py.
    mime = sniff_image_mime(data)
    if mime is None:
        raise HTTPException(
            status_code=400, detail="Unsupported image type (use JPEG, PNG or WebP)"
        )
    os.makedirs(settings.avatars_dir, exist_ok=True)
    with open(_avatar_path(user.id), "wb") as f:
        f.write(data)
    user.avatar_mime = mime
    user.avatar_updated_at = dt.datetime.now(dt.timezone.utc)
    await db.commit()
    await db.refresh(user)
    return _user_out(user)


@router.delete("/me/avatar", response_model=UserOut)
async def clear_avatar(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove the account's profile picture, falling back to the initial."""
    user.avatar_mime = None
    user.avatar_updated_at = None
    await db.commit()
    await db.refresh(user)
    try:
        os.remove(_avatar_path(user.id))
    except FileNotFoundError:
        pass
    return _user_out(user)


@router.get("/me/avatar")
async def avatar(user: User = Depends(get_current_user_media)):
    """Serve the picture. Authed via `?token=` too, so `Image.network` can
    fetch it without attaching custom headers."""
    path = _avatar_path(user.id)
    if user.avatar_mime is None or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="No profile picture")
    return FileResponse(path, media_type=user.avatar_mime)
