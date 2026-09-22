import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.user import User

from app.models.base import Base, Timestamps, UUIDPk


class Plan(UUIDPk, Timestamps, Base):
    """Tarif. Barcha limitlar shu yerda, admin paneldan tahrirlanadi (kodda qattiq yozilmaydi)."""

    __tablename__ = "plans"

    code: Mapped[str] = mapped_column(String(32), unique=True)
    name: Mapped[str] = mapped_column(String(64))
    price_uzs: Mapped[int] = mapped_column(Integer, default=0)
    max_groups: Mapped[int] = mapped_column(Integer)
    # O'qituvchining barcha faol guruhlaridagi jami faol o'quvchilar
    max_students: Mapped[int] = mapped_column(Integer)
    max_assignments_per_week: Mapped[int | None] = mapped_column(Integer)  # None = cheksiz
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class PlanRequest(UUIDPk, Timestamps, Base):
    """To'lov tizimi ulanmaguncha: o'qituvchi tarif so'raydi, admin to'lovni tekshirib tasdiqlaydi."""

    __tablename__ = "plan_requests"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    plan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("plans.id"))
    months: Mapped[int] = mapped_column(Integer, default=1)
    # So'rov paytidagi narx (keyin narx o'zgarsa ham tushum to'g'ri hisoblanadi)
    amount_uzs: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)  # pending | approved | rejected
    teacher_note: Mapped[str | None] = mapped_column(String(500))
    admin_note: Mapped[str | None] = mapped_column(String(500))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    decided_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))

    plan: Mapped[Plan] = relationship(lazy="joined")
    teacher: Mapped["User"] = relationship(lazy="joined", foreign_keys=[teacher_id])


class Subscription(UUIDPk, Timestamps, Base):
    __tablename__ = "subscriptions"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    plan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("plans.id"))
    status: Mapped[str] = mapped_column(String(16), default="active")  # active | canceled | expired
    current_period_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    plan: Mapped[Plan] = relationship(lazy="joined")
