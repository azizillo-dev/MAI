import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, Timestamps, UUIDPk
from app.models.user import User


class Subject(enum.StrEnum):
    MATH = "math"
    ENGLISH = "english"


class GroupStatus(enum.StrEnum):
    ACTIVE = "active"
    ARCHIVED = "archived"


class MemberStatus(enum.StrEnum):
    PENDING = "pending"  # o'qituvchi tasdig'ini kutmoqda (har bir yangi qo'shilish shu holatdan boshlanadi)
    ACTIVE = "active"
    REJECTED = "rejected"
    REMOVED = "removed"


class Group(UUIDPk, Timestamps, Base):
    __tablename__ = "groups"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(64))
    subject: Mapped[str] = mapped_column(String(16))
    grading_scale: Mapped[str] = mapped_column(String(8))
    # Guruh kodi: 8 belgi, chalkash belgilarsiz (0/O, 1/I/L yo'q), butun tizimda yagona.
    # Ekranda "K7M4-XQ9P" ko'rinishida.
    join_code: Mapped[str] = mapped_column(String(8), unique=True, index=True)
    # 8 xonali raqam, butun tizimda yagona. Ekranda "4829 1375".
    join_password: Mapped[str] = mapped_column(String(8), unique=True)
    # QR va havola ichidagi token: parolsiz qo'shilish uchun. Parol yangilanganda bu ham almashadi.
    invite_token: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    # Ustoz hamma qo'shilib bo'lgach yopib qo'yadi; yangi o'quvchi kerak bo'lsa qayta ochadi.
    # Yopiq bo'lsa kod, QR va havola ishlamaydi.
    join_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    status: Mapped[str] = mapped_column(String(16), default=GroupStatus.ACTIVE)

    teacher: Mapped[User] = relationship(lazy="joined")


class GroupMember(UUIDPk, Timestamps, Base):
    __tablename__ = "group_members"
    __table_args__ = (UniqueConstraint("group_id", "student_id"),)

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(16))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    group: Mapped[Group] = relationship(lazy="joined")
    student: Mapped[User] = relationship(lazy="joined")


class JoinAttempt(UUIDPk, Base):
    """Noto'g'ri parol urinishlari: parolni terib topishdan himoya."""

    __tablename__ = "join_attempts"

    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"))
    success: Mapped[bool] = mapped_column(Boolean)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
