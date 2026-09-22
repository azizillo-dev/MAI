"""Ro'yxatdan o'tish va kirish.

Oqim (ikkala rol uchun bir xil boshlanadi):
  1. POST /auth/otp/request   telefon -> SMS kod
  2. POST /auth/otp/verify    kod to'g'ri bo'lsa:
       - akkaunt bor   -> tokenlar (kirish)
       - akkaunt yo'q  -> registration_token (20 daqiqa)
  3. POST /auth/register/student | /auth/register/teacher  -> tokenlar
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.api.deps import DB, CurrentPrincipal, client_ip
from app.api.presenters import me_out
from app.core.config import get_settings
from app.core.errors import AppError, Conflict, Unauthorized
from app.core.phone import normalize_email, normalize_uz_phone
from app.core.security import create_registration_token, decode_registration_token
from app.models import Role, StudentProfile, TeacherProfile, User
from app.schemas.auth import (
    AuthOut,
    EmailRequestIn,
    EmailVerifyIn,
    OtpRequestIn,
    OtpRequestOut,
    OtpVerifyIn,
    OtpVerifyOut,
    RefreshIn,
    StudentRegisterIn,
    TeacherRegisterIn,
    TokensOut,
)
from app.schemas.common import Message
from app.services import otp, plans, sessions
from app.services.mailer import get_mailer, otp_email
from app.services.sms import SmsSender, get_sms_sender, otp_message

router = APIRouter(prefix="/auth", tags=["auth"])


async def _login_or_register(db: DB, request: Request, user: User | None, device: str | None,
                            *, phone: str | None = None, email: str | None = None) -> OtpVerifyOut:
    if user is None:
        return OtpVerifyOut(status="needs_registration", registration_token=create_registration_token(phone=phone, email=email))
    if not user.is_active:
        raise Unauthorized("USER_BLOCKED", "Akkaunt bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling")
    pair = await sessions.open_session(db, user, device, client_ip(request))
    await db.commit()
    return OtpVerifyOut(status="logged_in", tokens=TokensOut(**pair.__dict__), me=await me_out(db, user))


@router.post("/otp/request", response_model=OtpRequestOut)
async def request_code(
    body: OtpRequestIn, request: Request, db: DB, sms: SmsSender = Depends(get_sms_sender)
) -> OtpRequestOut:
    if get_settings().sms_provider == "disabled":
        raise AppError("SMS_DISABLED", "SMS orqali kirish vaqtincha o'chirilgan. Email orqali kiring", 503)
    phone = normalize_uz_phone(body.phone)

    async def deliver(target: str, code: str) -> None:
        await sms.send(target, otp_message(code))

    sent = await otp.request_otp(db, phone, client_ip(request), deliver)
    return OtpRequestOut(target=phone, channel="sms", phone=phone, expires_in=sent.expires_in,
                         resend_in=sent.resend_in, dev_code=sent.dev_code)


@router.post("/otp/verify", response_model=OtpVerifyOut)
async def verify_code(body: OtpVerifyIn, request: Request, db: DB) -> OtpVerifyOut:
    phone = normalize_uz_phone(body.phone)
    await otp.verify_otp(db, phone, body.code)
    user = await db.scalar(select(User).where(User.phone == phone))
    return await _login_or_register(db, request, user, body.device_name, phone=phone)


@router.post("/email/request", response_model=OtpRequestOut)
async def request_email_code(body: EmailRequestIn, request: Request, db: DB) -> OtpRequestOut:
    """Emailga 6 xonali kod yuboradi (SMS muqobili)."""
    email = normalize_email(body.email)
    mailer = get_mailer()

    async def deliver(target: str, code: str) -> None:
        subject, text, html = otp_email(code)
        await mailer.send(target, subject, text, html)

    sent = await otp.request_otp(db, email, client_ip(request), deliver)
    return OtpRequestOut(target=email, channel="email", expires_in=sent.expires_in,
                         resend_in=sent.resend_in, dev_code=sent.dev_code)


@router.post("/email/verify", response_model=OtpVerifyOut)
async def verify_email_code(body: EmailVerifyIn, request: Request, db: DB) -> OtpVerifyOut:
    email = normalize_email(body.email)
    await otp.verify_otp(db, email, body.code)
    user = await db.scalar(select(User).where(User.email == email))
    return await _login_or_register(db, request, user, body.device_name, email=email)


async def _create_user(db: DB, request: Request, body, role: Role, profile) -> AuthOut:
    phone, email = decode_registration_token(body.registration_token)
    taken = await db.scalar(select(User.id).where(User.phone == phone)) if phone else None
    if not taken and email:
        taken = await db.scalar(select(User.id).where(User.email == email))
    if taken:
        raise Conflict("PHONE_TAKEN", "Bu manzil bilan akkaunt allaqachon mavjud. Kirish bo'limidan foydalaning")

    user = User(
        phone=phone,
        email=email,
        role=role,
        first_name=body.first_name,
        last_name=body.last_name,
        middle_name=body.middle_name,
    )
    db.add(user)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise Conflict("PHONE_TAKEN", "Bu manzil bilan akkaunt allaqachon mavjud") from exc
    profile.user_id = user.id
    db.add(profile)
    if role == Role.TEACHER:
        await plans.start_trial(db, user.id)
    pair = await sessions.open_session(db, user, body.device_name, client_ip(request))
    await db.commit()
    await db.refresh(user)
    return AuthOut(tokens=TokensOut(**pair.__dict__), me=await me_out(db, user))


@router.post("/register/student", response_model=AuthOut, status_code=201)
async def register_student(body: StudentRegisterIn, request: Request, db: DB) -> AuthOut:
    # Ma'lumotlar darhol qulflanadi; o'zgartirish faqat ustoz ruxsati bilan
    profile = StudentProfile(birth_date=body.birth_date, gender=body.gender, is_locked=True)
    return await _create_user(db, request, body, Role.STUDENT, profile)


@router.post("/register/teacher", response_model=AuthOut, status_code=201)
async def register_teacher(body: TeacherRegisterIn, request: Request, db: DB) -> AuthOut:
    return await _create_user(db, request, body, Role.TEACHER, TeacherProfile(onboarding_answers={}))


@router.post("/refresh", response_model=TokensOut)
async def refresh(body: RefreshIn, db: DB) -> TokensOut:
    pair = await sessions.rotate_session(db, body.refresh_token)
    return TokensOut(**pair.__dict__)


@router.post("/logout", response_model=Message)
async def logout(p: CurrentPrincipal, db: DB) -> Message:
    await sessions.revoke_session(db, p.session_id)
    return Message()
