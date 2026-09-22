import enum
import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import JSON, Boolean, Date, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, Timestamps, UUIDPk


class Role(enum.StrEnum):
    STUDENT = "student"
    TEACHER = "teacher"
    ADMIN = "admin"


class User(UUIDPk, Timestamps, Base):
    __tablename__ = "users"

    # Kirish identifikatori: telefon YOKI email (kamida bittasi bo'ladi)
    phone: Mapped[str | None] = mapped_column(String(16), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(254), unique=True, index=True)
    # Faqat admin uchun (veb-panelga email + parol bilan kiradi)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(16), index=True)
    first_name: Mapped[str] = mapped_column(String(64))
    last_name: Mapped[str] = mapped_column(String(64))
    middle_name: Mapped[str | None] = mapped_column(String(64))
    locale: Mapped[str] = mapped_column(String(8), default="uz")
    avatar_key: Mapped[str | None] = mapped_column(String(128))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Birga-bir: JOIN bilan bitta so'rovda yuklanadi (har bir so'rovdagi auth uchun muhim)
    student: Mapped["StudentProfile | None"] = relationship(back_populates="user", lazy="joined")
    teacher: Mapped["TeacherProfile | None"] = relationship(back_populates="user", lazy="joined")

    @property
    def full_name(self) -> str:
        return f"{self.first_name} {self.last_name}"


class StudentProfile(Timestamps, Base):
    """O'quvchi ma'lumotlari ro'yxatdan o'tgach qulflanadi.

    O'zgartirish faqat o'qituvchi bergan bir martalik ruxsat (ProfileEditGrant) orqali.
    """

    __tablename__ = "student_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    birth_date: Mapped[date] = mapped_column(Date)
    gender: Mapped[str | None] = mapped_column(String(8))
    is_locked: Mapped[bool] = mapped_column(Boolean, default=True)

    user: Mapped[User] = relationship(back_populates="student")


class TeacherProfile(Timestamps, Base):
    __tablename__ = "teacher_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    onboarding_answers: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict)
    onboarding_completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Vazifa tekshiruvchi AI prompt'iga qo'shiladigan tayyor matn (onboarding javoblaridan yig'iladi)
    ai_context: Mapped[str | None] = mapped_column(Text)
    default_grading_scale: Mapped[str] = mapped_column(String(8), default="5")

    user: Mapped[User] = relationship(back_populates="teacher")


class ProfileEditGrant(UUIDPk, Base):
    """O'qituvchi o'quvchiga profilni BIR MARTA tahrirlash huquqini beradi."""

    __tablename__ = "profile_edit_grants"

    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Tahrirlashdan oldingi va keyingi qiymatlar (audit uchun)
    changes: Mapped[dict[str, Any] | None] = mapped_column(JSON)


class AuthSession(UUIDPk, Base):
    """Har bir qurilma uchun alohida sessiya. Refresh token har ishlatilganda almashadi."""

    __tablename__ = "auth_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    # Oldingi (almashtirilgan) token xeshi: qayta ishlatilsa, o'g'irlangan deb sessiya yopiladi
    previous_token_hash: Mapped[str | None] = mapped_column(String(64), index=True)
    device_name: Mapped[str | None] = mapped_column(String(128))
    ip: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_used_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class OtpCode(UUIDPk, Base):
    __tablename__ = "otp_codes"

    # Kod yuborilgan manzil: "+998901234567" yoki "ism@gmail.com"
    target: Mapped[str] = mapped_column(String(254), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    ip: Mapped[str | None] = mapped_column(String(64), index=True)
    attempts: Mapped[int] = mapped_column(default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

