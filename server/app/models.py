"""Database models."""
import datetime as dt

from sqlalchemy import (
    JSON,
    DateTime,
    Float,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    # Profile picture. The bytes live on disk (settings.avatars_dir/<user_id>);
    # these columns record that one exists, its mime type, and when it was last
    # replaced — the timestamp doubles as the client's cache-buster.
    avatar_mime: Mapped[str | None] = mapped_column(String(64), nullable=True)
    avatar_updated_at: Mapped[dt.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    connectors: Mapped[list["Connector"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class Connector(Base):
    """A per-user link to an external service (navidrome | abs). The secret
    (password or token) is stored encrypted."""

    __tablename__ = "connectors"
    __table_args__ = (UniqueConstraint("user_id", "kind"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[str] = mapped_column(String(32))  # navidrome | abs
    base_url: Mapped[str] = mapped_column(String(512))
    username: Mapped[str] = mapped_column(String(255))
    secret_enc: Mapped[str] = mapped_column(Text)  # encrypted password/token

    user: Mapped[User] = relationship(back_populates="connectors")


class Signal(Base):
    __tablename__ = "signals"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    ts: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    type: Mapped[str] = mapped_column(String(32))
    track_id: Mapped[str] = mapped_column(String(255))
    weight: Mapped[float] = mapped_column(Float, default=0.0)


class DownloadRequest(Base):
    """A user's request to acquire a track, fulfilled via slskd (Soulseek).

    status: pending → searching → downloading → completed | no_match | failed
    """

    __tablename__ = "download_requests"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    artist: Mapped[str] = mapped_column(String(512))
    title: Mapped[str] = mapped_column(String(512))
    album: Mapped[str | None] = mapped_column(String(512), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="pending", index=True)
    # slskd bookkeeping for the chosen file.
    slskd_username: Mapped[str | None] = mapped_column(String(255), nullable=True)
    slskd_filename: Mapped[str | None] = mapped_column(Text, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ChartTrack(Base):
    """A chart track downloaded into the rotating Charts folder. Kept rows are
    moved to the main library and never rotated out."""

    __tablename__ = "chart_tracks"
    __table_args__ = (UniqueConstraint("chart", "artist", "title"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    chart: Mapped[str] = mapped_column(String(32), index=True)  # au | worldwide
    artist: Mapped[str] = mapped_column(String(512))
    title: Mapped[str] = mapped_column(String(512))
    path: Mapped[str | None] = mapped_column(Text, nullable=True)  # file location
    kept: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class PlaylistCover(Base):
    """A custom cover image a user set for one of their Navidrome playlists.

    The bytes live on disk (settings.covers_dir/<user_id>_<playlist_id>); this
    row records that a custom cover exists, its mime type, and where it came
    from ('upload' | 'song'). Navidrome has no playlist-cover API, so the
    Musillow backend owns these overrides.
    """

    __tablename__ = "playlist_covers"
    __table_args__ = (UniqueConstraint("user_id", "playlist_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    playlist_id: Mapped[str] = mapped_column(String(255))
    mime: Mapped[str] = mapped_column(String(64), default="image/jpeg")
    kind: Mapped[str] = mapped_column(String(16), default="upload")  # upload | song
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Mix(Base):
    """A stored, rotating discovery mix (a Daily Mix or the Weekly).

    Mixes used to be recomputed from a seed on every request, which made them
    purely a view over the user's most-played tracks. They're now persisted,
    because the rotation rules need memory: a mix only rotates once its window
    has passed *and* the user has actually listened to it, so an untouched mix
    waits rather than being replaced unheard.
    """

    __tablename__ = "mixes"
    __table_args__ = (UniqueConstraint("user_id", "key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    key: Mapped[str] = mapped_column(String(64))  # daily-monday | weekly
    title: Mapped[str] = mapped_column(String(128))
    subtitle: Mapped[str] = mapped_column(String(255), default="")
    # Song snapshots in play order (id/title/artist/coverArt/duration).
    # Stored whole rather than as bare ids: Subsonic has no batch song lookup,
    # so re-resolving ids would mean one request per track on every home load.
    tracks: Mapped[list] = mapped_column(JSON, default=list)
    generated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    # The earliest this mix may be rotated — and only then if it's been played.
    rotates_after: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True))


class MixSeen(Base):
    """A track already offered to this user in a mix.

    Without this, "bring me songs I haven't heard" would just reshuffle the same
    unplayed pool forever. A surfaced-but-unsaved track goes on a cooldown so
    the next rotation is genuinely new; saved (starred) tracks are exempt,
    because keeping one is a request to hold on to it.
    """

    __tablename__ = "mix_seen"
    __table_args__ = (UniqueConstraint("user_id", "track_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    track_id: Mapped[str] = mapped_column(String(255))
    ts: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class DiscoverKeep(Base):
    __tablename__ = "discover_keep"
    __table_args__ = (UniqueConstraint("user_id", "track_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    track_id: Mapped[str] = mapped_column(String(255))
    ts: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class FeaturedPlaylist(Base):
    """The home spotlight, built from what this user has been listening to.

    Stored rather than recomputed on every home load for two reasons: building
    it costs upstream "similar songs" lookups, and a banner whose contents
    changed on every pull-to-refresh would be unreadable. It is rebuilt when
    there has been listening it hasn't seen yet — [seeded_through] is the
    timestamp of the newest play signal that fed the current build, so any play
    after it is what makes the next spotlight different.
    """

    __tablename__ = "featured_playlists"
    __table_args__ = (UniqueConstraint("user_id", name="uq_featured_user"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    subtitle: Mapped[str] = mapped_column(String(255), default="")
    # Song snapshots, same shape and for the same reason as Mix.tracks.
    tracks: Mapped[list] = mapped_column(JSON, default=list)
    generated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    seeded_through: Mapped[dt.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
