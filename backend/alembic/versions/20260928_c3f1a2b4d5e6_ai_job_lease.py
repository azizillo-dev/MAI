"""ai job lease and attempts

Revision ID: c3f1a2b4d5e6
Revises: 9a067f025d91
Create Date: 2026-09-28 10:00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c3f1a2b4d5e6'
down_revision: Union[str, Sequence[str], None] = '9a067f025d91'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    for table in ("assignments", "submissions"):
        with op.batch_alter_table(table) as batch:
            batch.add_column(sa.Column("ai_lease_until", sa.DateTime(timezone=True), nullable=True))
            batch.add_column(sa.Column("ai_attempts", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    for table in ("assignments", "submissions"):
        with op.batch_alter_table(table) as batch:
            batch.drop_column("ai_attempts")
            batch.drop_column("ai_lease_until")
