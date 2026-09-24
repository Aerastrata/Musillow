"""Pydantic request/response schemas."""
from pydantic import BaseModel, ConfigDict


class RegisterIn(BaseModel):
    username: str
    password: str
    email: str | None = None


class LoginIn(BaseModel):
    username: str
    password: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    email: str | None = None
    # Whether a profile picture is set, and a cache-buster that changes each
    # time it is replaced (epoch seconds; 0 when there is no picture).
    avatar: bool = False
    avatarVersion: int = 0


class UpdateMeIn(BaseModel):
    username: str | None = None
    email: str | None = None
    password: str | None = None


class ConnectorIn(BaseModel):
    kind: str  # navidrome | abs
    baseUrl: str
    username: str
    secret: str  # password (navidrome) or token/password (abs)


class ConnectorOut(BaseModel):
    kind: str
    baseUrl: str
    username: str
    connected: bool = True


class SignalIn(BaseModel):
    type: str
    trackId: str


class PlaylistCreateIn(BaseModel):
    name: str
    songIds: list[str] = []


class PlaylistUpdateIn(BaseModel):
    """Rename and/or replace the full song list (reorder + removal)."""
    name: str | None = None
    songIds: list[str] | None = None


class PlaylistAddIn(BaseModel):
    songIds: list[str]
