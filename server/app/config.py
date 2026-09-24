"""Environment configuration for the Musillow backend."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Async DB URL (app). Alembic derives a sync URL from this.
    database_url: str = (
        "postgresql+asyncpg://musillow:musillow@db:5432/musillow"
    )

    # JWT signing.
    jwt_secret: str = "change-me-in-production"
    jwt_expire_minutes: int = 60 * 24 * 30  # 30 days

    # Symmetric key used to encrypt stored connector secrets at rest.
    secret_key: str = "change-me-too-in-production"

    # slskd (Soulseek daemon) — fulfils download requests. Reachable from the
    # container via the host-gateway mapping in docker-compose.
    slskd_url: str = "http://host.docker.internal:5030"
    slskd_api_key: str = ""

    # In-container mounts: where slskd drops finished files, and the Navidrome
    # library we move them into so they get scanned + become playable.
    downloads_dir: str = "/downloads"
    library_dir: str = "/library"
    # Rotating charts folder (under the scanned library so it plays, but capped
    # to the current chart and emptied on rotation unless a track is kept).
    charts_dir: str = "/library/Charts"

    # Where custom playlist cover images are stored (a persisted volume). Files
    # are named "<user_id>_<playlist_id>"; the DB tracks their mime type.
    covers_dir: str = "/data/covers"
    # Where account profile pictures are stored (a persisted volume). Files are
    # named "<user_id>"; the users table tracks the mime type and set time.
    avatars_dir: str = "/data/avatars"

    @property
    def sync_database_url(self) -> str:
        """Sync SQLAlchemy URL for Alembic migrations."""
        return self.database_url.replace("+asyncpg", "+psycopg2")


settings = Settings()
