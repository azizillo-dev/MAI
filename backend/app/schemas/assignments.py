import uuid
from datetime import datetime

from pydantic import Field, field_validator

from app.schemas.common import Schema


class BookOut(Schema):
    id: uuid.UUID
    title: str
    page_count: int
    page_offset: int
    # Kitobdagi oxirgi bosma bet raqami (ustozga oralig'ni to'g'ri tanlashga yordam)
    last_printed_page: int


class BookUpdateIn(Schema):
    title: str | None = Field(default=None, min_length=2, max_length=120)
    page_offset: int | None = Field(default=None, ge=1)


class Item(Schema):
    number: str = Field(min_length=1, max_length=20)
    text: str = Field(min_length=1, max_length=2000)
    answer: str | None = Field(default=None, max_length=500)


class Criterion(Schema):
    name: str = Field(min_length=1, max_length=80)
    weight: int = Field(ge=1, le=100)
    description: str = Field(default="", max_length=400)


class ContentUpdateIn(Schema):
    items: list[Item] | None = Field(default=None, max_length=200)
    rubric: list[Criterion] | None = Field(default=None, max_length=10)

    @field_validator("rubric")
    @classmethod
    def _weights(cls, v: list[Criterion] | None) -> list[Criterion] | None:
        if v and sum(c.weight for c in v) != 100:
            raise ValueError("Mezonlar foizi yig'indisi 100 bo'lishi kerak")
        return v


class SubmissionStats(Schema):
    submitted: int
    graded: int
    needs_review: int
    members: int


class AssignmentOut(Schema):
    id: uuid.UUID
    group_id: uuid.UUID
    group_name: str
    title: str
    instructions: str | None
    source_type: str
    book: BookOut | None
    page_from: int | None
    page_to: int | None
    problems: str | None
    items: list[dict]
    rubric: list[dict]
    image_urls: list[str]
    prepare_error: str | None
    status: str
    due_at: datetime
    allow_late: bool
    late_penalty_percent: int
    published_at: datetime | None
    created_at: datetime
    stats: SubmissionStats | None = None


class SubmissionOut(Schema):
    id: uuid.UUID
    assignment_id: uuid.UUID
    student_id: uuid.UUID
    student_name: str
    status: str
    submitted_at: datetime
    is_late: bool
    attempt: int
    text_answer: str | None
    file_urls: list[str]
    ai_items: list[dict]
    ai_confidence: float | None
    ai_matches_assignment: bool | None
    feedback_student: str | None
    # Faqat ustozga
    note_teacher: str | None = None
    ai_score_percent: float | None = None
    teacher_score: float | None
    teacher_comment: str | None
    final_score: float | None
    grading_scale: str


class ReviewIn(Schema):
    score: float = Field(ge=0, le=100)
    comment: str | None = Field(default=None, max_length=1000)


class StudentAssignmentOut(Schema):
    id: uuid.UUID
    group_id: uuid.UUID
    group_name: str
    subject: str
    teacher_name: str
    title: str
    instructions: str | None
    source_type: str
    items: list[dict]
    rubric: list[dict]
    image_urls: list[str]
    book_title: str | None
    page_from: int | None
    page_to: int | None
    problems: str | None
    due_at: datetime
    allow_late: bool
    late_penalty_percent: int
    grading_scale: str
    submission: SubmissionOut | None
