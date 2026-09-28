"""O'qituvchi jetonlari: adminlardan sotib olinadi, yaxshi o'qigan o'quvchiga sovg'a qilinadi.

To'lov tizimi ulanguncha xarid "so'rov" ko'rinishida: admin to'lovni qabul qilib tasdiqlaydi va
o'qituvchi hisobiga jeton tushadi. Hisob daftar (ledger) ko'rinishida saqlanadi — tarix yo'qolmaydi.
"""

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, NotFound
from app.core.security import utcnow
from app.models import BadgeAward, GiftJeton, JetonLedger, JetonOrder, User

DEFAULT_JETONS = [
    {"code": "sinf_yulduzi", "name": "Sinf yulduzi", "description": "Guruhdagi eng yaxshi natija uchun",
     "icon": "star", "tier": "gold", "price_uzs": 12_000, "sort_order": 1},
    {"code": "oltin_qalam", "name": "Oltin qalam", "description": "Toza va chiroyli rasmiylashtirilgan ish uchun",
     "icon": "pen", "tier": "gold", "price_uzs": 6_000, "sort_order": 2},
    {"code": "aql_chirogi", "name": "Aql chirog'i", "description": "Ijodiy, noodatiy yechim uchun",
     "icon": "lightbulb", "tier": "purple", "price_uzs": 8_000, "sort_order": 3},
    {"code": "tirishqoq", "name": "Tirishqoq", "description": "Katta o'sish va mehnat uchun",
     "icon": "rocket", "tier": "blue", "price_uzs": 6_000, "sort_order": 4},
    {"code": "yosh_matematik", "name": "Yosh matematik", "description": "Matematikadagi alo natija uchun",
     "icon": "calculate", "tier": "green", "price_uzs": 8_000, "sort_order": 5},
    {"code": "soz_ustasi", "name": "So'z ustasi", "description": "Ingliz tilidagi alo natija uchun",
     "icon": "translate", "tier": "green", "price_uzs": 8_000, "sort_order": 6},
    {"code": "ustoz_mehri", "name": "Ustoz mehri", "description": "Ustozdan alohida minnatdorchilik",
     "icon": "heart", "tier": "silver", "price_uzs": 4_000, "sort_order": 7},
    {"code": "chempion", "name": "Chempion", "description": "Musobaqa yoki olimpiada g'olibiga",
     "icon": "medal", "tier": "gold", "price_uzs": 20_000, "sort_order": 8},
]


async def seed_jetons(db: AsyncSession) -> None:
    existing = set(await db.scalars(select(GiftJeton.code)))
    for data in DEFAULT_JETONS:
        if data["code"] not in existing:
            db.add(GiftJeton(**data))
    await db.commit()


def jeton_dict(j: GiftJeton) -> dict:
    return {"code": j.code, "name": j.name, "description": j.description, "icon": j.icon, "tier": j.tier,
            "price_uzs": j.price_uzs, "is_active": j.is_active}


async def catalog(db: AsyncSession, *, active_only: bool = True) -> list[GiftJeton]:
    q = select(GiftJeton).order_by(GiftJeton.sort_order)
    if active_only:
        q = q.where(GiftJeton.is_active.is_(True))
    return list(await db.scalars(q))


async def balances(db: AsyncSession, teacher_id: uuid.UUID) -> dict[str, int]:
    rows = await db.execute(
        select(JetonLedger.jeton_code, func.sum(JetonLedger.delta))
        .where(JetonLedger.teacher_id == teacher_id)
        .group_by(JetonLedger.jeton_code)
    )
    return {code: int(total) for code, total in rows if total}


async def _get_jeton(db: AsyncSession, code: str) -> GiftJeton:
    j = await db.scalar(select(GiftJeton).where(GiftJeton.code == code))
    if j is None or not j.is_active:
        raise NotFound("JETON_NOT_FOUND", "Bunday jeton yo'q")
    return j


async def create_order(db: AsyncSession, teacher: User, code: str, quantity: int, note: str | None) -> JetonOrder:
    j = await _get_jeton(db, code)
    pending = await db.scalar(
        select(func.count()).select_from(JetonOrder)
        .where(JetonOrder.teacher_id == teacher.id, JetonOrder.status == "pending")
    )
    if pending >= 3:
        raise Conflict("ORDERS_PENDING", "Oldingi buyurtmalaringiz ko'rib chiqilmoqda. Admin tez orada bog'lanadi")
    order = JetonOrder(teacher_id=teacher.id, jeton_code=j.code, quantity=quantity,
                       amount_uzs=j.price_uzs * quantity, teacher_note=(note or "").strip() or None)
    db.add(order)
    await db.commit()
    await db.refresh(order)
    return order


async def decide_order(db: AsyncSession, order_id: uuid.UUID, approve: bool, note: str | None) -> JetonOrder:
    order = await db.get(JetonOrder, order_id)
    if order is None:
        raise NotFound("ORDER_NOT_FOUND", "Buyurtma topilmadi")
    if order.status != "pending":
        raise Conflict("ORDER_DECIDED", "Buyurtma allaqachon ko'rib chiqilgan")
    now = utcnow()
    order.status = "approved" if approve else "rejected"
    order.admin_note = (note or "").strip() or None
    order.decided_at = now
    if approve:
        db.add(JetonLedger(teacher_id=order.teacher_id, jeton_code=order.jeton_code, delta=order.quantity,
                           kind="purchase", ref_id=order.id, created_at=now))
    await db.commit()
    await db.refresh(order)
    return order


async def gift(db: AsyncSession, teacher: User, student_id: uuid.UUID, code: str, note: str | None) -> BadgeAward:
    # Aylanma importdan qochish uchun shu yerda
    from app.services.gamification import invalidate_stats
    from app.services.groups import teacher_has_student

    j = await _get_jeton(db, code)
    if not await teacher_has_student(db, teacher.id, student_id):
        raise NotFound("STUDENT_NOT_FOUND", "O'quvchi topilmadi")
    # Bir vaqtda ikki marta bosilsa ham balans manfiyga tushmasligi uchun: avval o'qituvchi qatori
    # qulflanadi, balans qulfdan KEYIN yangi so'rov bilan hisoblanadi (ikkinchi so'rov birinchisini kutadi)
    await db.execute(select(User.id).where(User.id == teacher.id).with_for_update())
    balance = await db.scalar(
        select(func.coalesce(func.sum(JetonLedger.delta), 0))
        .where(JetonLedger.teacher_id == teacher.id, JetonLedger.jeton_code == code)
    )
    if balance <= 0:
        raise AppError("JETON_BALANCE_EMPTY", f"«{j.name}» jetoningiz qolmagan. Avval sotib oling", 409)
    now = utcnow()
    award = BadgeAward(student_id=student_id, badge_code=code, source="gift", given_by=teacher.id, awarded_at=now,
                       meta={"name": j.name, "icon": j.icon, "tier": j.tier, "teacher": teacher.full_name,
                             "note": (note or "").strip()[:200] or None})
    db.add(award)
    await db.flush()
    db.add(JetonLedger(teacher_id=teacher.id, jeton_code=code, delta=-1, kind="gift", ref_id=award.id, created_at=now))
    await db.commit()
    await db.refresh(award)
    invalidate_stats(student_ids=[student_id])
    return award


async def given_count(db: AsyncSession, teacher_id: uuid.UUID) -> int:
    return int(await db.scalar(
        select(func.count()).select_from(BadgeAward)
        .where(BadgeAward.given_by == teacher_id, BadgeAward.source == "gift")
    ) or 0)
