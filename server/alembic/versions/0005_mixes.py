"""persisted rotating mixes

Revision ID: 0005
Revises: 0004
Create Date: 2026-08-28
"""
from alembic import op
import sqlalchemy as sa

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mixes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("key", sa.String(64), nullable=False),
        sa.Column("title", sa.String(128), nullable=False),
        sa.Column("subtitle", sa.String(255), nullable=False, server_default=""),
        sa.Column("tracks", sa.JSON(), nullable=False),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("rotates_after", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "key", name="uq_mix_user_key"),
    )
    op.create_index("ix_mixes_user_id", "mixes", ["user_id"])

    op.create_table(
        "mix_seen",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("track_id", sa.String(255), nullable=False),
        sa.Column(
            "ts",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "track_id", name="uq_mix_seen"),
    )
    op.create_index("ix_mix_seen_user_id", "mix_seen", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_mix_seen_user_id", "mix_seen")
    op.drop_table("mix_seen")
    op.drop_index("ix_mixes_user_id", "mixes")
    op.drop_table("mixes")
