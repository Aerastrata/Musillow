"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-08-24
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("username", sa.String(64), nullable=False),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_users_username", "users", ["username"], unique=True)
    op.create_unique_constraint("uq_users_email", "users", ["email"])

    op.create_table(
        "connectors",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("base_url", sa.String(512), nullable=False),
        sa.Column("username", sa.String(255), nullable=False),
        sa.Column("secret_enc", sa.Text(), nullable=False),
        sa.UniqueConstraint("user_id", "kind", name="uq_connector_user_kind"),
    )
    op.create_index("ix_connectors_user_id", "connectors", ["user_id"])

    op.create_table(
        "signals",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "ts",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("type", sa.String(32), nullable=False),
        sa.Column("track_id", sa.String(255), nullable=False),
        sa.Column("weight", sa.Float(), nullable=False, server_default="0"),
    )
    op.create_index("ix_signals_user_id", "signals", ["user_id"])

    op.create_table(
        "discover_keep",
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
        sa.UniqueConstraint("user_id", "track_id", name="uq_keep_user_track"),
    )
    op.create_index("ix_discover_keep_user_id", "discover_keep", ["user_id"])


def downgrade() -> None:
    op.drop_table("discover_keep")
    op.drop_table("signals")
    op.drop_table("connectors")
    op.drop_table("users")
