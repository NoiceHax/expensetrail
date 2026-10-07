"""create expenses table

Revision ID: 0001
Revises:
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "expenses",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("amount", sa.Float, nullable=False),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("spent_on", sa.Date, nullable=False),
    )
    op.create_index("ix_expenses_category", "expenses", ["category"])


def downgrade():
    op.drop_index("ix_expenses_category", table_name="expenses")
    op.drop_table("expenses")
