"""download requests (slskd fulfilment)

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-27
"""
from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "download_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("artist", sa.String(512), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("album", sa.String(512), nullable=True),
        sa.Column("status", sa.String(32), nullable=False, server_default="pending"),
        sa.Column("slskd_username", sa.String(255), nullable=True),
        sa.Column("slskd_filename", sa.Text(), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_download_requests_user_id", "download_requests", ["user_id"]
    )
    op.create_index(
        "ix_download_requests_status", "download_requests", ["status"]
    )


def downgrade() -> None:
    op.drop_index("ix_download_requests_status", "download_requests")
    op.drop_index("ix_download_requests_user_id", "download_requests")
    op.drop_table("download_requests")
