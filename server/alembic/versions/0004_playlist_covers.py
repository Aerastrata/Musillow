"""custom playlist cover overrides

Revision ID: 0004
Revises: 0003
Create Date: 2026-08-28
"""
from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "playlist_covers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("playlist_id", sa.String(255), nullable=False),
        sa.Column(
            "mime", sa.String(64), nullable=False, server_default="image/jpeg"
        ),
        sa.Column("kind", sa.String(16), nullable=False, server_default="upload"),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "playlist_id", name="uq_playlist_cover"),
    )
    op.create_index(
        "ix_playlist_covers_user_id", "playlist_covers", ["user_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_playlist_covers_user_id", "playlist_covers")
    op.drop_table("playlist_covers")
