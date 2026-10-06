"""Taqdimot sayti: ochiq ma'lumotlar, parol bilan yopilgan iqtisodiy bo'lim va APK yuklash.

Qiymatlar `site_settings` jadvalida saqlanadi va admin paneldan tahrirlanadi. Bazada yozuv bo'lmasa —
quyidagi standart qiymatlar (o'lchangan haqiqiy token sarfi asosida) ishlatiladi.
"""

import asyncio
import base64
import hashlib
import io
import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, NotFound, Unauthorized
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


# ---------------------------------------------------------------- Jamoa (asoschilar)
# Saytdagi "Jamoa" bo'limi. Rasmlar kichik (480px, ~40 KB) — bazada base64 ko'rinishida saqlanadi,
# shuning uchun alohida fayl ombori va imzolangan havola kerak emas.

DEMO_EMAIL_DOMAIN = "demo.mentorai.uz"  # tools/showcase_seed.py yaratgan talabalar

FOUNDERS_KEY = "founders"
MAX_FOUNDERS = 12
PHOTO_SIDE = 480


async def _founders_raw(db: AsyncSession) -> list[dict]:
    return list((await _get(db, FOUNDERS_KEY) or {}).get("items", []))


async def _save_founders(db: AsyncSession, items: list[dict]) -> None:
    await _put(db, FOUNDERS_KEY, {"items": items})


def founder_out(f: dict) -> dict:
    photo = f"/api/v1/site/founders/{f['id']}/photo?v={f['photo_v']}" if f.get("photo") else None
    return {"id": f["id"], "name": f["name"], "role": f["role"], "bio": f.get("bio") or "", "photo_url": photo}


async def founders(db: AsyncSession) -> list[dict]:
    return [founder_out(f) for f in await _founders_raw(db)]


def _find(items: list[dict], fid: str) -> int:
    for i, f in enumerate(items):
        if f["id"] == fid:
            return i
    raise NotFound("FOUNDER_NOT_FOUND", "Jamoa a'zosi topilmadi")


async def add_founder(db: AsyncSession, name: str, role: str, bio: str | None) -> dict:
    items = await _founders_raw(db)
    if len(items) >= MAX_FOUNDERS:
        raise AppError("FOUNDERS_LIMIT", f"Jamoada ko'pi bilan {MAX_FOUNDERS} kishi bo'lishi mumkin", 422)
    f = {"id": uuid.uuid4().hex[:12], "name": name.strip(), "role": role.strip(), "bio": (bio or "").strip()}
    items.append(f)
    await _save_founders(db, items)
    return founder_out(f)


async def update_founder(db: AsyncSession, fid: str, data: dict) -> dict:
    items = await _founders_raw(db)
    f = items[_find(items, fid)]
    for k in ("name", "role", "bio"):
        if data.get(k) is not None:
            f[k] = data[k].strip()
    await _save_founders(db, items)
    return founder_out(f)


async def delete_founder(db: AsyncSession, fid: str) -> None:
    items = await _founders_raw(db)
    items.pop(_find(items, fid))
    await _save_founders(db, items)


async def move_founder(db: AsyncSession, fid: str, up: bool) -> list[dict]:
    items = await _founders_raw(db)
    i = _find(items, fid)
    j = i - 1 if up else i + 1
    if 0 <= j < len(items):
        items[i], items[j] = items[j], items[i]
        await _save_founders(db, items)
    return [founder_out(f) for f in items]


def _square_photo(data: bytes) -> bytes:
    from PIL import Image, ImageOps, UnidentifiedImageError

    try:
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise AppError("PHOTO_INVALID", "Rasmni o'qib bo'lmadi. JPG yoki PNG yuklang", 422) from exc
    # Yuz odatda rasmning yuqori qismida — kvadratni biroz yuqoriroqdan qirqamiz
    img = ImageOps.fit(img, (PHOTO_SIDE, PHOTO_SIDE), Image.LANCZOS, centering=(0.5, 0.35))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=86, optimize=True)
    return out.getvalue()


async def set_founder_photo(db: AsyncSession, fid: str, data: bytes) -> dict:
    items = await _founders_raw(db)
    f = items[_find(items, fid)]
    jpg = _square_photo(data)
    f["photo"] = base64.b64encode(jpg).decode()
    f["photo_v"] = hashlib.sha1(jpg).hexdigest()[:10]  # rasm almashsa havola ham o'zgaradi (kesh uchun)
    await _save_founders(db, items)
    return founder_out(f)


async def founder_photo(db: AsyncSession, fid: str) -> bytes:
    items = await _founders_raw(db)
    f = items[_find(items, fid)]
    if not f.get("photo"):
        raise NotFound("PHOTO_NOT_FOUND", "Rasm yuklanmagan")
    return base64.b64decode(f["photo"])


async def public_info(db: AsyncSession) -> dict:
    plans = await _plans(db)
    # Taqdimot uchun yaratilgan demo talabalar (DEMO_EMAIL_DOMAIN) ochiq statistikaga kirmaydi —
    # saytda faqat haqiqiy foydalanish ko'rsatiladi
    real = ~User.email.like(f"%@{DEMO_EMAIL_DOMAIN}")
    teachers = await db.scalar(select(func.count()).select_from(User).where(User.role == Role.TEACHER))
    students = await db.scalar(select(func.count()).select_from(User).where(User.role == Role.STUDENT, real))
    checked = await db.scalar(
        select(func.count()).select_from(Submission).join(User, User.id == Submission.student_id)
        .where(Submission.status == SubmissionStatus.GRADED, real)
    )
    return {
        "plans": [p for p in plans if p["code"] != TRIAL],
        "trial": next((p for p in plans if p["code"] == TRIAL), None),
        "stats": {"teachers": teachers, "students": students, "checked": checked},
        "downloads": await downloads(db),
        "secret_enabled": await has_secret_password(db),
        "founders": await founders(db),
    }
