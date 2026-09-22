import enum
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, Timestamps, UUIDPk
from app.models.group import Group
from app.models.user import User


class Book(UUIDPk, Timestamps, Base):
    """O'qituvchining PDF kitoblari. Bir kitob hamma guruhlarida qayta ishlatiladi."""

    __tablename__ = "books"

    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(120))
    file_key: Mapped[str] = mapped_column(String(128))
    page_count: Mapped[int] = mapped_column(Integer)
    # Kitobdagi 1-bet PDF faylning nechanchi sahifasida (muqova, mundarija sababli farq qiladi).
    # Ustoz bir marta kiritadi; "34-bet" -> PDF sahifasi = 34 + page_offset - 1
    page_offset: Mapped[int] = mapped_column(Integer, default=1)


class SourceType(enum.StrEnum):
    BOOK = "book"  # PDF kitob + sahifa/misol oralig'i
    IMAGES = "images"  # misollar rasmi
    TEXT = "text"  # matnli topshiriq (krossvord, insho...)


class AssignmentStatus(enum.StrEnum):
    PREPARING = "preparing"  # AI misollarni ajratmoqda
    REVIEW = "review"  # ustoz AI ajratganini tekshirib tasdiqlashi kerak
    PUBLISHED = "published"  # o'quvchilar ko'radi
    FAILED = "failed"  # tayyorlashda xato (ustoz qayta urinadi yoki qo'lda to'ldiradi)


class Assignment(UUIDPk, Timestamps, Base):
    __tablename__ = "assignments"

    group_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"), index=True)
    teacher_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(120))
    instructions: Mapped[str | None] = mapped_column(Text)
    source_type: Mapped[str] = mapped_column(String(16))

    book_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("books.id", ondelete="SET NULL"))
    page_from: Mapped[int | None] = mapped_column(Integer)  # kitobdagi (bosma) raqam
    page_to: Mapped[int | None] = mapped_column(Integer)
    problems: Mapped[str | None] = mapped_column(String(120))  # "56-78" yoki "3, 5, 7-10"

    # AI ajratgan va ustoz tasdiqlagan misollar: [{"number": "56", "text": "...", "answer": "..."}]
    items: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    # Matnli vazifa uchun baholash mezonlari: [{"name", "weight", "description"}]
    rubric: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    prepare_error: Mapped[str | None] = mapped_column(Text)

    status: Mapped[str] = mapped_column(String(16), default=AssignmentStatus.PREPARING, index=True)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    allow_late: Mapped[bool] = mapped_column(Boolean, default=True)
    # Kechikkan ish uchun jarima foizi (0 = jarima yo'q)
    late_penalty_percent: Mapped[int] = mapped_column(Integer, default=0)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    group: Mapped[Group] = relationship(lazy="joined")
    book: Mapped[Book | None] = relationship(lazy="joined")
    images: Mapped[list["AssignmentImage"]] = relationship(
        lazy="selectin", order_by="AssignmentImage.position", cascade="all, delete-orphan"
    )


class AssignmentImage(UUIDPk, Base):
    __tablename__ = "assignment_images"

    assignment_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("assignments.id", ondelete="CASCADE"), index=True)
    file_key: Mapped[str] = mapped_column(String(128))
    mime: Mapped[str] = mapped_column(String(32))
    position: Mapped[int] = mapped_column(Integer)


class SubmissionStatus(enum.StrEnum):
    GRADING = "grading"  # AI tekshirmoqda
    GRADED = "graded"  # baho o'quvchiga chiqdi
    NEEDS_REVIEW = "needs_review"  # AI ishonchi past yoki vazifaga mos emas: ustoz ko'rishi kerak
    FAILED = "failed"  # AI xatosi: ustoz qo'lda baholaydi


class Submission(UUIDPk, Timestamps, Base):
    __tablename__ = "submissions"
    __table_args__ = (UniqueConstraint("assignment_id", "student_id"),)

    assignment_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("assignments.id", ondelete="CASCADE"), index=True)
    student_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    text_answer: Mapped[str | None] = mapped_column(Text)
    submitted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_late: Mapped[bool] = mapped_column(Boolean, default=False)
    attempt: Mapped[int] = mapped_column(Integer, default=1)

    status: Mapped[str] = mapped_column(String(16), default=SubmissionStatus.GRADING, index=True)
    # AI natijasi: har bir misol bo'yicha hukm va izoh
    ai_items: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list)
    ai_score_percent: Mapped[float | None] = mapped_column(Float)
    ai_confidence: Mapped[float | None] = mapped_column(Float)
    ai_matches_assignment: Mapped[bool | None] = mapped_column(Boolean)
    feedback_student: Mapped[str | None] = mapped_column(Text)
    note_teacher: Mapped[str | None] = mapped_column(Text)
    graded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Ustoz bahoni o'zgartirsa, yakuniy baho shu
    teacher_score: Mapped[float | None] = mapped_column(Float)
    teacher_comment: Mapped[str | None] = mapped_column(Text)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Guruh shkalasidagi yakuniy baho (5/10/100): o'quvchiga shu ko'rinadi
    final_score: Mapped[float | None] = mapped_column(Float)

    assignment: Mapped[Assignment] = relationship(lazy="joined")
    student: Mapped[User] = relationship(lazy="joined")
    files: Mapped[list["SubmissionFile"]] = relationship(
        lazy="selectin", order_by="SubmissionFile.position", cascade="all, delete-orphan"
    )


class SubmissionFile(UUIDPk, Base):
    __tablename__ = "submission_files"

    submission_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("submissions.id", ondelete="CASCADE"), index=True)
    file_key: Mapped[str] = mapped_column(String(128))
    mime: Mapped[str] = mapped_column(String(32))
    position: Mapped[int] = mapped_column(Integer)
    # Bir xil rasmni ikki o'quvchi yuborsa aniqlash uchun (ko'chirishga signal)
    sha256: Mapped[str] = mapped_column(String(64), index=True)


class AiRun(UUIDPk, Base):
    """Har bir AI chaqiruvi: xarajat va sifatni admin panelda kuzatish uchun."""

    __tablename__ = "ai_runs"

    kind: Mapped[str] = mapped_column(String(16))  # prepare | grade
    teacher_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    assignment_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("assignments.id", ondelete="SET NULL"))
    submission_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("submissions.id", ondelete="SET NULL"))
    provider: Mapped[str] = mapped_column(String(16))
    model: Mapped[str] = mapped_column(String(64))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cache_read_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cache_write_tokens: Mapped[int] = mapped_column(Integer, default=0)
    duration_ms: Mapped[int] = mapped_column(Integer, default=0)
    success: Mapped[bool] = mapped_column(Boolean)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
