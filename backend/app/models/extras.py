"""Murojaatlar, o'qituvchi jetonlari va sayt sozlamalari."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, Timestamps, UUIDPk
from app.models.user import User


class SupportMessage(UUIDPk, Timestamps, Base):
    """"Yordam va taklif": foydalanuvchi yozadi, admin javob beradi."""

    __tablename__ = "support_messages"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(16))  # help | suggestion | bug
    text: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default="open", index=True)  # open | answered | closed
    admin_reply: Mapped[str | None] = mapped_column(Text)
    replied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(lazy="selectin")


class GiftJeton(UUIDPk, Timestamps, Base):
    """O'qituvchi adminlardan sotib olib, o'quvchisiga sovg'a qiladigan jeton turi."""

    __tablename__ = "gift_jetons"

    code: Mapped[str] = mapped_column(String(40), unique=True)
    name: Mapped[str] = mapped_column(String(64))
    description: Mapped[str] = mapped_column(String(255))
    icon: Mapped[str] = mapped_column(String(32))  # ilovadagi ikonka kaliti
    tier: Mapped[str] = mapped_column(String(16))  # bronze | silver | gold | blue | green | purple
    price_uzs: Mapped[int] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class JetonOrder(UUIDPk, Timestamps, Base):
    """Jeton xaridi: to'lov tizimi ulanguncha admin to'lovni qabul qilib tasdiqlaydi."""

    __tablename__ = "jeton_orders"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    jeton_code: Mapped[str] = mapped_column(String(40))
    quantity: Mapped[int] = mapped_column(Integer)
    amount_uzs: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(16), default="pending", index=True)  # pending | approved | rejected
    teacher_note: Mapped[str | None] = mapped_column(String(500))
    admin_note: Mapped[str | None] = mapped_column(String(500))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    teacher: Mapped[User] = relationship(lazy="selectin", foreign_keys=[teacher_id])


class JetonLedger(UUIDPk, Base):
    """O'qituvchi jeton hisobi: +xarid, -sovg'a. Balans yig'indidan hisoblanadi (tarix saqlanadi)."""

    __tablename__ = "jeton_ledger"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    jeton_code: Mapped[str] = mapped_column(String(40))
    delta: Mapped[int] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(String(16))  # purchase | gift | admin
    ref_id: Mapped[uuid.UUID | None] = mapped_column()  # buyurtma yoki sovg'a (BadgeAward) id
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SiteSetting(Base):
    """Sayt (taqdimot) sozlamalari: kalkulyator parametrlari, maxfiy bo'lim paroli va h.k."""

    __tablename__ = "site_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[dict[str, Any]] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
