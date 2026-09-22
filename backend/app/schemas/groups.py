import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import Field, field_validator

from app.schemas.common import Schema

SubjectLit = Literal["math", "english"]
ScaleLit = Literal["5", "10", "100"]


def _clean_group_name(value: str) -> str:
    value = " ".join(value.split())
    if not 2 <= len(value) <= 40:
        raise ValueError("2 dan 40 gacha belgi bo'lishi kerak")
    return value


class GroupCreateIn(Schema):
    name: str
    subject: SubjectLit
    grading_scale: ScaleLit | None = None

    _name = field_validator("name")(_clean_group_name)


class GroupUpdateIn(Schema):
    name: str | None = None
    grading_scale: ScaleLit | None = None

    @field_validator("name")
    @classmethod
    def _n(cls, v: str | None) -> str | None:
        return None if v is None else _clean_group_name(v)


class TeacherGroupOut(Schema):
    id: uuid.UUID
    name: str
    subject: str
    grading_scale: str
    status: str
    join_enabled: bool
    join_code: str  # formatlangan: "K7M4-XQ9P"
    join_password: str  # "48291375"
    invite_url: str
    members_active: int
    members_pending: int
    created_at: datetime


class TeacherBrief(Schema):
    id: uuid.UUID
    full_name: str
    avatar_url: str | None = None


class MembershipOut(Schema):
    group_id: uuid.UUID
    group_name: str
    subject: str
    grading_scale: str
    teacher: TeacherBrief
    status: str
    requested_at: datetime
    decided_at: datetime | None


class JoinPreviewIn(Schema):
    code: str = Field(min_length=4, max_length=20)


class JoinPreviewOut(Schema):
    code: str
    group_name: str
    subject: str
    teacher_name: str
    members_active: int


class JoinIn(Schema):
    code: str = Field(min_length=4, max_length=20)
    password: str | None = Field(default=None, max_length=20)
    invite_token: str | None = Field(default=None, max_length=64)


class MemberOut(Schema):
    student_id: uuid.UUID
    first_name: str
    last_name: str
    full_name: str
    phone: str | None
    email: str | None = None
    avatar_url: str | None = None
    status: str
    requested_at: datetime
    decided_at: datetime | None


class JoinToggleIn(Schema):
    enabled: bool


class ApproveAllOut(Schema):
    approved: int
    left_pending: int
    limit: int


class PlanUsageOut(Schema):
    plan: dict[str, Any]
    status: str  # trial | active | expired
    ends_at: datetime | None
    days_left: int
    groups_used: int
    students_used: int


class OnboardingIn(Schema):
    answers: dict[str, Any]


class OnboardingOut(Schema):
    answers: dict[str, Any]
    ai_context: str
    completed_at: datetime | None
