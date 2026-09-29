"""Taqdimot sayti: ochiq ma'lumotlar, parol bilan yopilgan iqtisodiy bo'lim va APK yuklash.

Qiymatlar `site_settings` jadvalida saqlanadi va admin paneldan tahrirlanadi. Bazada yozuv bo'lmasa —
quyidagi standart qiymatlar (o'lchangan haqiqiy token sarfi asosida) ishlatiladi.
"""

import asyncio

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import Unauthorized
from app.core.security import hash_password, utcnow, verify_password
from app.models import Plan, Role, SiteSetting, Submission, SubmissionStatus, User
from app.services.plans import TRIAL, plan_dict

# Narxlar: Gemini API rasmiy narxi (1 mln token uchun, USD). Token sarfi — haqiqiy tekshiruvlardan o'lchangan.
DEFAULT_ECONOMICS = {
    "usd_uzs": 12700,
    "model": "gemini-3.6-flash",
    "price_in": 0.75,
    "price_out": 3.75,
    "price_in_2027": 1.50,
    "price_out_2027": 7.50,
    "grade_in_tokens": 1780,
    "grade_out_tokens": 3190,
    "prepare_in_tokens": 1240,
    "prepare_out_tokens": 5980,
    "assistant_in_tokens": 3000,
    "assistant_out_tokens": 800,
    "assistant_calls_per_month": 80,
    "assignments_per_week": 2,
    "submit_rate": 0.85,
    "resubmit_rate": 0.10,
    "overhead": 0.15,
    "server_usd_month": 12,
    "paying_teachers": 50,
    "payment_fee": 0.02,
    "notes": "Token sarfi 2026-09-28 da haqiqiy tekshiruvlardan o'lchandi: 10 ta misolli daftar rasmi "
             "(1600x2200) — 1 780 kirish, 3 190 chiqish tokeni. Chiqishning asosiy qismi AI'ning "
             "fikrlashi (thinking). Gemini narxlari 2027-yil 1-yanvardan 2 baravar oshadi.",
}

DEFAULT_DOWNLOADS = {
    "version": "1.1.1",
    "arm64_url": "/downloads/MentorAI-arm64.apk",
    "legacy_url": "/downloads/MentorAI-eski-telefonlar.apk",
    "arm64_size_mb": 30,
    "legacy_size_mb": 26,
    "note": "Android 7.0 va undan yuqori",
}


async def _get(db: AsyncSession, key: str) -> dict | None:
    row = await db.get(SiteSetting, key)
    return row.value if row else None


async def _put(db: AsyncSession, key: str, value: dict) -> None:
    row = await db.get(SiteSetting, key)
    if row is None:
        db.add(SiteSetting(key=key, value=value, updated_at=utcnow()))
    else:
        row.value = value
        row.updated_at = utcnow()
    await db.commit()


async def economics(db: AsyncSession) -> dict:
    return {**DEFAULT_ECONOMICS, **(await _get(db, "economics") or {})}


async def downloads(db: AsyncSession) -> dict:
    return {**DEFAULT_DOWNLOADS, **(await _get(db, "downloads") or {})}


async def set_economics(db: AsyncSession, data: dict) -> dict:
    # Faqat ma'lum kalitlar, turi standart qiymat turi bilan bir xil bo'lishi kerak
    clean = {}
    for k, default in DEFAULT_ECONOMICS.items():
        if k in data and data[k] is not None:
            clean[k] = str(data[k])[:2000] if isinstance(default, str) else float(data[k])
    await _put(db, "economics", clean)
    return await economics(db)


async def set_downloads(db: AsyncSession, data: dict) -> dict:
    clean = {k: data[k] for k in DEFAULT_DOWNLOADS if k in data and data[k] is not None}
    await _put(db, "downloads", clean)
    return await downloads(db)


async def set_secret_password(db: AsyncSession, password: str) -> None:
    await _put(db, "secret", {"hash": hash_password(password)})


async def has_secret_password(db: AsyncSession) -> bool:
    return bool((await _get(db, "secret") or {}).get("hash"))


async def open_secret(db: AsyncSession, password: str) -> dict:
    stored = (await _get(db, "secret") or {}).get("hash")
    if not stored or not verify_password(password, stored):
        await asyncio.sleep(1)  # parolni tanlab topishni sekinlashtiradi
        raise Unauthorized("SECRET_PASSWORD_INVALID", "Parol noto'g'ri")
    return {"economics": await economics(db), "plans": await _plans(db)}


async def _plans(db: AsyncSession) -> list[dict]:
    rows = await db.scalars(select(Plan).where(Plan.is_active.is_(True)).order_by(Plan.sort_order))
    return [plan_dict(p) for p in rows]


async def public_info(db: AsyncSession) -> dict:
    plans = await _plans(db)
    teachers = await db.scalar(select(func.count()).select_from(User).where(User.role == Role.TEACHER))
    students = await db.scalar(select(func.count()).select_from(User).where(User.role == Role.STUDENT))
    checked = await db.scalar(
        select(func.count()).select_from(Submission).where(Submission.status == SubmissionStatus.GRADED)
    )
    return {
        "plans": [p for p in plans if p["code"] != TRIAL],
        "trial": next((p for p in plans if p["code"] == TRIAL), None),
        "stats": {"teachers": teachers, "students": students, "checked": checked},
        "downloads": await downloads(db),
        "secret_enabled": await has_secret_password(db),
    }
