"""the listening-driven home spotlight

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-04
"""
from alembic import op
import sqlalchemy as sa

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "featured_playlists",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("subtitle", sa.String(255), nullable=False, server_default=""),
        sa.Column("tracks", sa.JSON(), nullable=False),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        # The newest play signal folded into the current build; listening past
        # it is what makes the spotlight due for a rebuild.
        sa.Column("seeded_through", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", name="uq_featured_user"),
    )
    op.create_index(
        "ix_featured_playlists_user_id", "featured_playlists", ["user_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_featured_playlists_user_id", "featured_playlists")
    op.drop_table("featured_playlists")
