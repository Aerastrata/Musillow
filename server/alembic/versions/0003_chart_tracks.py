"""chart tracks (rotating charts folder)

Revision ID: 0003
Revises: 0002
Create Date: 2026-08-27
"""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "chart_tracks",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("chart", sa.String(32), nullable=False),
        sa.Column("artist", sa.String(512), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("path", sa.Text(), nullable=True),
        sa.Column("kept", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint("chart", "artist", "title", name="uq_chart_track"),
    )
    op.create_index("ix_chart_tracks_chart", "chart_tracks", ["chart"])


def downgrade() -> None:
    op.drop_index("ix_chart_tracks_chart", "chart_tracks")
    op.drop_table("chart_tracks")
