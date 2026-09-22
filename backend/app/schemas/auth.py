import uuid
from datetime import date
from typing import Literal

from pydantic import Field

from app.schemas.common import BirthDate, PersonName, Schema


class OtpRequestIn(Schema):
    phone: str = Field(max_length=32)


class EmailRequestIn(Schema):
    email: str = Field(max_length=254)


class EmailVerifyIn(Schema):
    email: str = Field(max_length=254)
    code: str = Field(pattern=r"^\d{4,8}$")
    device_name: str | None = Field(default=None, max_length=128)


class OtpRequestOut(Schema):
    # Kod yuborilgan manzil (telefon yoki email) — ilova "kod ... ga yuborildi" deb ko'rsatadi
    target: str
    channel: Literal["sms", "email"]
    phone: str | None = None
    expires_in: int
    resend_in: int
    dev_code: str | None = None


class OtpVerifyIn(Schema):
    phone: str = Field(max_length=32)
    code: str = Field(pattern=r"^\d{4,8}$")
    device_name: str | None = Field(default=None, max_length=128)


class TokensOut(Schema):
    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "bearer"


class StudentInfo(Schema):
    birth_date: date
    gender: str | None
    is_locked: bool
    can_edit: bool


class TeacherInfo(Schema):
    onboarding_completed: bool
    default_grading_scale: str


class MeOut(Schema):
    id: uuid.UUID
    phone: str | None
    email: str | None = None
    role: str
    first_name: str
    last_name: str
    middle_name: str | None
    full_name: str
    locale: str
    avatar_url: str | None = None
    student: StudentInfo | None = None
    teacher: TeacherInfo | None = None
    # Ilova qaysi ekranga yo'naltirishi kerak: teacher_onboarding | home
    next_step: str


class OtpVerifyOut(Schema):
    status: Literal["logged_in", "needs_registration"]
    tokens: TokensOut | None = None
    me: MeOut | None = None
    registration_token: str | None = None


class _RegisterBase(Schema):
    registration_token: str
    first_name: PersonName
    last_name: PersonName
    middle_name: PersonName | None = None
    device_name: str | None = Field(default=None, max_length=128)


class StudentRegisterIn(_RegisterBase):
    birth_date: BirthDate
    gender: Literal["male", "female"] | None = None


class TeacherRegisterIn(_RegisterBase):
    pass


class AuthOut(Schema):
    tokens: TokensOut
    me: MeOut


class RefreshIn(Schema):
    refresh_token: str = Field(min_length=20, max_length=256)


class MeUpdateIn(Schema):
    locale: Literal["uz", "uz-Cyrl", "ru", "en"] | None = None
    # Faqat o'qituvchi o'zgartira oladi (o'quvchi ma'lumotlari ustoz ruxsatisiz qulflangan)
    first_name: PersonName | None = None
    last_name: PersonName | None = None


class StudentProfileUpdateIn(Schema):
    first_name: PersonName | None = None
    last_name: PersonName | None = None
    middle_name: PersonName | None = None
    birth_date: BirthDate | None = None
    gender: Literal["male", "female"] | None = None
