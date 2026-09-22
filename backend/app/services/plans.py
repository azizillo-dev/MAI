"""Tariflar va obunalar.

  trial     — 14 kun bepul (yangi o'qituvchi avtomatik oladi): 1 guruh, 30 o'quvchi
  standard  — 20 000 so'm/oy: 1 guruh, 30 o'quvchi
  pro       — 70 000 so'm/oy: 3 guruh, 90 o'quvchi

To'lov tizimi ulanmaguncha: o'qituvchi ilovadan so'rov yuboradi, admin panelda tasdiqlanadi.
Narx va limitlar `plans` jadvalida — admin paneldan o'zgartiriladi.
"""

import uuid
from datetime import timedelta

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import Forbidden
from app.core.security import as_utc, utcnow
from app.models import Group, GroupMember, GroupStatus, MemberStatus, Plan, Subscription

TRIAL = "trial"
DAYS_PER_MONTH = 30

DEFAULT_PLANS = [
    {"code": TRIAL, "name": "Sinov (14 kun)", "price_uzs": 0, "max_groups": 1, "max_students": 30,
     "max_assignments_per_week": None, "is_default": False, "sort_order": 0},
    {"code": "standard", "name": "Standart", "price_uzs": 20_000, "max_groups": 1, "max_students": 30,
     "max_assignments_per_week": None, "is_default": False, "sort_order": 1},
    {"code": "pro", "name": "Pro", "price_uzs": 70_000, "max_groups": 3, "max_students": 90,
     "max_assignments_per_week": None, "is_default": False, "sort_order": 2},
]


async def seed_plans(db: AsyncSession) -> None:
    existing = set(await db.scalars(select(Plan.code)))
    for data in DEFAULT_PLANS:
        if data["code"] not in existing:
            db.add(Plan(**data))
    # Eski "free" tarifi o'rniga 14 kunlik sinov keldi
    await db.execute(update(Plan).where(Plan.code == "free").values(is_active=False, is_default=False))
    await db.commit()


async def get_plan(db: AsyncSession, code: str) -> Plan | None:
    return await db.scalar(select(Plan).where(Plan.code == code))


async def start_trial(db: AsyncSession, teacher_id: uuid.UUID) -> Subscription:
    plan = await get_plan(db, TRIAL)
    if plan is None:
        raise RuntimeError("Sinov tarifi topilmadi: seed_plans() ishga tushirilmagan")
    sub = Subscription(
        teacher_id=teacher_id, plan_id=plan.id, status="active",
        current_period_end=utcnow() + timedelta(days=get_settings().trial_days),
    )
    db.add(sub)
    await db.flush()
    return sub


async def active_subscription(db: AsyncSession, teacher_id: uuid.UUID) -> Subscription | None:
    """Hozir amal qilayotgan obuna. Umuman obunasi bo'lmagan (eski) o'qituvchiga sinov ochiladi."""
    sub = await db.scalar(
        select(Subscription)
        .where(Subscription.teacher_id == teacher_id, Subscription.status == "active",
               Subscription.current_period_end > utcnow())
        .order_by(Subscription.current_period_end.desc())
        .limit(1)
    )
    if sub is not None:
        return sub
    ever = await db.scalar(select(func.count()).select_from(Subscription).where(Subscription.teacher_id == teacher_id))
    if not ever:
        sub = await start_trial(db, teacher_id)
        await db.commit()
        await db.refresh(sub)
        return sub
    return None


async def effective_plan(db: AsyncSession, teacher_id: uuid.UUID) -> Plan | None:
    sub = await active_subscription(db, teacher_id)
    return sub.plan if sub else None


async def require_plan(db: AsyncSession, teacher_id: uuid.UUID) -> Plan:
    """Yangi guruh/vazifa yaratishdan oldin: tarif faol bo'lishi shart."""
    plan = await effective_plan(db, teacher_id)
    if plan is None:
        raise Forbidden(
            "PLAN_EXPIRED",
            "Tarif muddati tugagan. Davom etish uchun Profil → Tarif bo'limidan tarif tanlang",
        )
    return plan


async def active_group_count(db: AsyncSession, teacher_id: uuid.UUID) -> int:
    return await db.scalar(
        select(func.count()).select_from(Group).where(Group.teacher_id == teacher_id, Group.status == GroupStatus.ACTIVE)
    )


async def active_student_count(db: AsyncSession, teacher_id: uuid.UUID) -> int:
    """O'qituvchining faol guruhlaridagi noyob faol o'quvchilar soni.

    Bir o'quvchi shu o'qituvchining ikki guruhida bo'lsa, bir marta hisoblanadi.
    """
    return await db.scalar(
        select(func.count(func.distinct(GroupMember.student_id)))
        .join(Group, Group.id == GroupMember.group_id)
        .where(
            Group.teacher_id == teacher_id,
            Group.status == GroupStatus.ACTIVE,
            GroupMember.status == MemberStatus.ACTIVE,
        )
    )


def plan_dict(plan: Plan) -> dict:
    return {
        "code": plan.code,
        "name": plan.name,
        "price_uzs": plan.price_uzs,
        "max_groups": plan.max_groups,
        "max_students": plan.max_students,
        "max_assignments_per_week": plan.max_assignments_per_week,
    }


async def usage(db: AsyncSession, teacher_id: uuid.UUID) -> dict:
    sub = await active_subscription(db, teacher_id)
    if sub is None:
        last = await db.scalar(
            select(Subscription).where(Subscription.teacher_id == teacher_id)
            .order_by(Subscription.current_period_end.desc()).limit(1)
        )
        plan, status, ends_at = (last.plan if last else None), "expired", (last.current_period_end if last else None)
    else:
        plan, ends_at = sub.plan, sub.current_period_end
        status = "trial" if plan.code == TRIAL else "active"
    days_left = max(0, (as_utc(ends_at) - utcnow()).days + (1 if status != "expired" else 0)) if ends_at else 0
    return {
        "plan": plan_dict(plan) if plan else {"code": "none", "name": "Tarif yo'q", "price_uzs": 0, "max_groups": 0,
                                              "max_students": 0, "max_assignments_per_week": None},
        "status": status,
        "ends_at": ends_at,
        "days_left": days_left if status != "expired" else 0,
        "groups_used": await active_group_count(db, teacher_id),
        "students_used": await active_student_count(db, teacher_id),
    }


async def extend_subscription(db: AsyncSession, teacher_id: uuid.UUID, plan: Plan, months: int) -> Subscription:
    """Admin tasdiqlaganda: shu tarif faol bo'lsa muddati uzayadi, aks holda bugundan yangi obuna.

    Sinov yoki boshqa tarif faol bo'lsa, u yopiladi (yangi tarif darhol kuchga kiradi).
    """
    now = utcnow()
    current = await db.scalar(
        select(Subscription)
        .where(Subscription.teacher_id == teacher_id, Subscription.status == "active",
               Subscription.current_period_end > now)
        .order_by(Subscription.current_period_end.desc()).limit(1)
    )
    days = DAYS_PER_MONTH * months
    if current is not None and current.plan_id == plan.id:
        current.current_period_end = as_utc(current.current_period_end) + timedelta(days=days)
        await db.flush()
        return current
    if current is not None:
        current.status = "canceled"
    sub = Subscription(teacher_id=teacher_id, plan_id=plan.id, status="active",
                       current_period_end=now + timedelta(days=days))
    db.add(sub)
    await db.flush()
    return sub
