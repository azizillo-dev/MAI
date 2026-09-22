import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, UUIDPk


class XpEvent(UUIDPk, Base):
    """XP jurnali: har bir baholangan ish uchun bitta yozuv.

    Balans alohida saqlanmaydi, jurnaldan yig'iladi: ustoz bahoni o'zgartirsa, shu yozuv yangilanadi
    va hamma joyda (reyting, daraja) avtomatik to'g'ri bo'ladi.
    """

    __tablename__ = "xp_events"

    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"), index=True)
    submission_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("submissions.id", ondelete="CASCADE"), unique=True
    )
    points: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class BadgeAward(UUIDPk, Base):
    """Nishon (jeton). source: system (avtomatik), monthly (oy medali), gift (ustoz hadyasi — keyingi bosqich)."""

    __tablename__ = "badge_awards"

    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    badge_code: Mapped[str] = mapped_column(String(40), index=True)
    source: Mapped[str] = mapped_column(String(16), default="system")
    group_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("groups.id", ondelete="SET NULL"))
    # Hadya qilgan ustoz (gift uchun)
    given_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # Oy medali uchun davr: "2026-08" (bir oy uchun medal ikki marta berilmasligi uchun)
    period: Mapped[str | None] = mapped_column(String(7), index=True)
    # Oy medali uchun: {"rank": 1, "points": 225, "group": "7-B"}
    meta: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    awarded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
