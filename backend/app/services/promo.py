"""Promo kodlar: tekshirish, chegirmani hisoblash va statistika.

Kod faqat "kutilmoqda" yoki "tasdiqlangan" so'rovlarda ishlatilgan hisoblanadi — admin so'rovni rad etsa,
o'qituvchi kodni qayta ishlata oladi va umumiy limitdan ham joy bo'shaydi.
"""

import re
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError
from app.core.security import utcnow
from app.models import Plan, PlanRequest, PromoCode
from app.services.assignments import TASHKENT

CODE_RE = re.compile(r"^[A-Z0-9_-]{3,32}$")
COUNTED = ("pending", "approved")


def normalize(code: str) -> str:
    return code.strip().upper()


def end_of_day(d: date) -> datetime:
    """Admin sanani kiritadi — kod shu kun oxirigacha (Toshkent vaqti) amal qiladi."""
    return datetime.combine(d, time(23, 59, 59), tzinfo=TASHKENT)


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)  # SQLite vaqt zonasini saqlamaydi


def discount_for(promo: PromoCode, full_uzs: int) -> int:
    d = round(full_uzs * promo.value / 100) if promo.kind == "percent" else promo.value
    return max(0, min(full_uzs, d))


@dataclass
class Quote:
    promo: PromoCode | None
    full_uzs: int
    discount_uzs: int
    amount_uzs: int

    def as_dict(self) -> dict:
        return {
            "code": self.promo.code if self.promo else None,
            "kind": self.promo.kind if self.promo else None,
            "value": self.promo.value if self.promo else None,
            "full_uzs": self.full_uzs,
            "discount_uzs": self.discount_uzs,
            "amount_uzs": self.amount_uzs,
        }


def _invalid(code: str, message: str) -> AppError:
    return AppError(code, message, 422)


async def quote(db: AsyncSession, teacher_id: uuid.UUID, plan: Plan, months: int, code: str | None,
                *, lock: bool = False) -> Quote:
    """Narxni hisoblaydi. Kod noto'g'ri bo'lsa aniq sababini aytadigan xato qaytaradi."""
    full = plan.price_uzs * months
    if not code or not code.strip():
        return Quote(None, full, 0, full)

    q = select(PromoCode).where(PromoCode.code == normalize(code))
    if lock:
        q = q.with_for_update()  # bir vaqtda kelgan so'rovlar limitdan oshib ketmasin
    promo = await db.scalar(q)
    if promo is None or not promo.is_active:
        raise _invalid("PROMO_INVALID", "Bunday promo kod yo'q yoki faol emas")
    if promo.valid_until and _aware(promo.valid_until) < utcnow():
        raise _invalid("PROMO_EXPIRED", "Promo kodning muddati tugagan")
    if promo.plan_code and promo.plan_code != plan.code:
        target = await db.scalar(select(Plan.name).where(Plan.code == promo.plan_code))
        raise _invalid("PROMO_PLAN_MISMATCH", f"Bu promo kod faqat «{target or promo.plan_code}» tarifi uchun")
    used_by_me = await db.scalar(select(PlanRequest.id).where(
        PlanRequest.promo_code_id == promo.id, PlanRequest.teacher_id == teacher_id,
        PlanRequest.status.in_(COUNTED)).limit(1))
    if used_by_me:
        raise _invalid("PROMO_ALREADY_USED", "Siz bu promo kodni allaqachon ishlatgansiz")
    if promo.max_uses is not None and await uses(db, promo.id) >= promo.max_uses:
        raise _invalid("PROMO_USED_UP", "Bu promo kodning limiti tugagan")

    discount = discount_for(promo, full)
    return Quote(promo, full, discount, full - discount)


async def uses(db: AsyncSession, promo_id: uuid.UUID) -> int:
    return await db.scalar(select(func.count()).select_from(PlanRequest).where(
        PlanRequest.promo_code_id == promo_id, PlanRequest.status.in_(COUNTED)))


async def stats(db: AsyncSession) -> dict[uuid.UUID, dict]:
    """Har bir kod uchun: nechta so'rovda ishlatilgan, tasdiqlangan tushum va berilgan chegirma."""
    approved = PlanRequest.status == "approved"
    rows = await db.execute(
        select(
            PlanRequest.promo_code_id,
            func.count().filter(PlanRequest.status.in_(COUNTED)),
            func.count().filter(approved),
            func.coalesce(func.sum(PlanRequest.amount_uzs).filter(approved), 0),
            func.coalesce(func.sum(PlanRequest.discount_uzs).filter(approved), 0),
        ).where(PlanRequest.promo_code_id.is_not(None)).group_by(PlanRequest.promo_code_id)
    )
    return {pid: {"uses": u, "approved": a, "revenue_uzs": int(rev), "discount_uzs": int(disc)}
            for pid, u, a, rev, disc in rows}


def promo_dict(p: PromoCode, st: dict | None = None) -> dict:
    st = st or {"uses": 0, "approved": 0, "revenue_uzs": 0, "discount_uzs": 0}
    expired = bool(p.valid_until and _aware(p.valid_until) < utcnow())
    return {
        "id": p.id, "code": p.code, "kind": p.kind, "value": p.value, "plan_code": p.plan_code,
        "max_uses": p.max_uses, "valid_until": p.valid_until, "is_active": p.is_active, "note": p.note,
        "created_at": p.created_at, "expired": expired, **st,
    }
