"""Ustoz va o'quvchi o'rtasidagi yozishma."""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, Timestamps, UUIDPk
from app.models.user import User


class Conversation(UUIDPk, Timestamps, Base):
    """Bitta ustoz va bitta o'quvchi o'rtasidagi suhbat (juftlik uchun yagona)."""

    __tablename__ = "conversations"
    __table_args__ = (UniqueConstraint("teacher_id", "student_id"),)

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    last_message_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    last_message_text: Mapped[str | None] = mapped_column(Text)
    last_sender_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # O'qilmagan xabarlar soni — har bir tomon uchun alohida (ro'yxat va belgi uchun arzon)
    teacher_unread: Mapped[int] = mapped_column(Integer, default=0)
    student_unread: Mapped[int] = mapped_column(Integer, default=0)
    # Qarshi tomon oxirgi marta qachon o'qigan — "o'qildi" belgisi uchun
    teacher_read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    student_read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    teacher: Mapped[User] = relationship(foreign_keys=[teacher_id], lazy="selectin")
    student: Mapped[User] = relationship(foreign_keys=[student_id], lazy="selectin")


class ChatMessage(UUIDPk, Base):
    __tablename__ = "chat_messages"
    __table_args__ = (Index("ix_chat_messages_conv_created", "conversation_id", "created_at"),)

    conversation_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"))
    sender_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
