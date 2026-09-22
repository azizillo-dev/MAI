from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import AppError, TooManyRequests
from app.core.security import as_utc, generate_otp, hash_otp, otp_matches, utcnow
from app.models import OtpCode


@dataclass
class OtpSent:
    expires_in: int
    resend_in: int
    dev_code: str | None = None


async def request_otp(
    db: AsyncSession, phone: str, ip: str | None, deliver: Callable[[str, str], Awaitable[None]]
) -> OtpSent:
    """[phone] — kod yuboriladigan manzil (telefon yoki email). [deliver](manzil, kod) kodni yetkazadi."""
    s = get_settings()
    now = utcnow()
    hour_ago = now - timedelta(hours=1)

    last = await db.scalar(
        select(OtpCode).where(OtpCode.target == phone).order_by(OtpCode.created_at.desc()).limit(1)
    )
    if last is not None:
        wait = s.otp_resend_seconds - int((now - as_utc(last.created_at)).total_seconds())
        if wait > 0:
            raise TooManyRequests(
                "OTP_RESEND_TOO_SOON", f"Yangi kodni {wait} soniyadan keyin so'rashingiz mumkin", details={"retry_after": wait}
            )

    per_phone = await db.scalar(
        select(func.count()).select_from(OtpCode).where(OtpCode.target == phone, OtpCode.created_at >= hour_ago)
    )
    if per_phone >= s.otp_max_per_phone_hour:
        raise TooManyRequests(
            "OTP_LIMIT", "Kod juda ko'p so'raldi. 1 soatdan keyin urinib ko'ring", details={"retry_after": 3600}
        )
    if ip:
        per_ip = await db.scalar(
            select(func.count()).select_from(OtpCode).where(OtpCode.ip == ip, OtpCode.created_at >= hour_ago)
        )
        if per_ip >= s.otp_max_per_ip_hour:
            raise TooManyRequests("OTP_LIMIT", "Juda ko'p urinish. Keyinroq qayta urinib ko'ring", details={"retry_after": 3600})

    # Eski kodlar bekor qilinadi: faqat oxirgi yuborilgan kod ishlaydi
    await db.execute(
        update(OtpCode).where(OtpCode.target == phone, OtpCode.consumed_at.is_(None)).values(consumed_at=now)
    )
    code = generate_otp(s.otp_length)
    db.add(
        OtpCode(
            target=phone,
            code_hash=hash_otp(phone, code),
            ip=ip,
            created_at=now,
            expires_at=now + timedelta(seconds=s.otp_ttl_seconds),
        )
    )
    await db.flush()
    # Kod yetkazilmasa saqlanmaydi (tranzaksiya commit qilinmaydi)
    await deliver(phone, code)
    await db.commit()

    return OtpSent(
        expires_in=s.otp_ttl_seconds,
        resend_in=s.otp_resend_seconds,
        dev_code=code if (s.otp_dev_echo and not s.is_production) else None,
    )


async def verify_otp(db: AsyncSession, phone: str, code: str) -> None:
    s = get_settings()
    now = utcnow()
    otp = await db.scalar(
        select(OtpCode)
        .where(OtpCode.target == phone, OtpCode.consumed_at.is_(None))
        .order_by(OtpCode.created_at.desc())
        .limit(1)
        .with_for_update()
    )
    if otp is None or as_utc(otp.expires_at) < now:
        raise AppError("OTP_EXPIRED", "Kod muddati tugagan. Yangi kod so'rang")
    if otp.attempts >= s.otp_max_attempts:
        raise AppError("OTP_TOO_MANY_ATTEMPTS", "Urinishlar tugadi. Yangi kod so'rang")

    if not otp_matches(phone, code, otp.code_hash):
        otp.attempts += 1
        left = s.otp_max_attempts - otp.attempts
        await db.commit()
        if left <= 0:
            raise AppError("OTP_TOO_MANY_ATTEMPTS", "Urinishlar tugadi. Yangi kod so'rang")
        raise AppError("OTP_INVALID", f"Kod noto'g'ri. Yana {left} ta urinish qoldi", details={"attempts_left": left})

    otp.consumed_at = now
    await db.commit()
