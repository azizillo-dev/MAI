"""Admin panel API: so'rovlarni tasdiqlash, o'qituvchilar, tariflar, tushumlar.

Admin email + parol bilan kiradi (akkaunt `python -m app.cli create-admin` bilan yaratiladi).
"""

import asyncio
import uuid
from datetime import timedelta
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query, Request
from pydantic import Field
from sqlalchemy import func, or_, select

from app.api.deps import DB, CurrentPrincipal, client_ip
from app.api.presenters import me_out
from app.core.errors import AppError, Forbidden, NotFound, Unauthorized
from app.core.security import utcnow, verify_password
from app.models import (
    AiRun,
    GiftJeton,
    Group,
    GroupMember,
    GroupStatus,
    JetonOrder,
    MemberStatus,
    Plan,
    PlanRequest,
    Role,
    Submission,
    SupportMessage,
    User,
)
from app.schemas.auth import TokensOut
from app.schemas.common import Schema
from app.services import jetons, plans, sessions, site
from app.services.assignments import TASHKENT

router = APIRouter(prefix="/admin", tags=["admin"])


async def get_admin(p: CurrentPrincipal) -> User:
    if p.user.role != Role.ADMIN:
        raise Forbidden("ROLE_FORBIDDEN", "Faqat administratorlar uchun")
    return p.user


CurrentAdmin = Annotated[User, Depends(get_admin)]


class AdminLoginIn(Schema):
    email: str = Field(max_length=254)
    password: str = Field(min_length=6, max_length=200)


@router.post("/login")
async def admin_login(body: AdminLoginIn, request: Request, db: DB) -> dict:
    user = await db.scalar(select(User).where(User.email == body.email.strip().lower(), User.role == Role.ADMIN))
    if user is None or not verify_password(body.password, user.password_hash):
        await asyncio.sleep(1)  # parolni terib topishni sekinlashtiradi
        raise Unauthorized("LOGIN_INVALID", "Email yoki parol noto'g'ri")
    pair = await sessions.open_session(db, user, "Admin panel", client_ip(request))
    await db.commit()
    return {"tokens": TokensOut(**pair.__dict__).model_dump(), "me": (await me_out(db, user)).model_dump(mode="json")}


# ---------------------------------------------------------------- Statistika


@router.get("/stats")
async def stats(admin: CurrentAdmin, db: DB) -> dict:
    now = utcnow()
    local = now.astimezone(TASHKENT)
    month_start = local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    teachers = list(await db.scalars(select(User).where(User.role == Role.TEACHER)))
    by_status = {"trial": 0, "active": 0, "expired": 0}
    for t in teachers:
        by_status[(await plans.usage(db, t.id))["status"]] += 1

    approved = PlanRequest.status == "approved"
    revenue_month = await db.scalar(select(func.coalesce(func.sum(PlanRequest.amount_uzs), 0))
                                    .where(approved, PlanRequest.decided_at >= month_start))
    revenue_total = await db.scalar(select(func.coalesce(func.sum(PlanRequest.amount_uzs), 0)).where(approved))
    months = []
    for i in range(5, -1, -1):
        start = (month_start - timedelta(days=31 * i)).replace(day=1)
        end = (start + timedelta(days=32)).replace(day=1)
        amount = await db.scalar(select(func.coalesce(func.sum(PlanRequest.amount_uzs), 0))
                                 .where(approved, PlanRequest.decided_at >= start, PlanRequest.decided_at < end))
        months.append({"month": start.strftime("%Y-%m"), "amount": int(amount)})

    day_ago = now - timedelta(days=1)
    return {
        "teachers": len(teachers),
        "students": await db.scalar(select(func.count()).select_from(User).where(User.role == Role.STUDENT)),
        "groups": await db.scalar(select(func.count()).select_from(Group).where(Group.status == GroupStatus.ACTIVE)),
        "subscriptions": by_status,
        "pending_requests": await db.scalar(select(func.count()).select_from(PlanRequest).where(PlanRequest.status == "pending")),
        "support_open": await db.scalar(select(func.count()).select_from(SupportMessage).where(SupportMessage.status == "open")),
        "jeton_orders_pending": await db.scalar(
            select(func.count()).select_from(JetonOrder).where(JetonOrder.status == "pending")),
        "revenue_month": int(revenue_month),
        "revenue_total": int(revenue_total),
        "revenue_by_month": months,
        "submissions_today": await db.scalar(select(func.count()).select_from(Submission).where(Submission.submitted_at >= day_ago)),
        "ai_calls_today": await db.scalar(select(func.count()).select_from(AiRun).where(AiRun.created_at >= day_ago)),
        "ai_errors_today": await db.scalar(select(func.count()).select_from(AiRun).where(
            AiRun.created_at >= day_ago, AiRun.success.is_(False))),
        "ai_tokens_today": int(await db.scalar(select(func.coalesce(func.sum(AiRun.input_tokens + AiRun.output_tokens), 0))
                                               .where(AiRun.created_at >= day_ago))),
    }


# ---------------------------------------------------------------- So'rovlar


def _request(r: PlanRequest) -> dict:
    return {
        "id": r.id,
        "teacher": {"id": r.teacher.id, "name": r.teacher.full_name, "phone": r.teacher.phone, "email": r.teacher.email},
        "plan": plans.plan_dict(r.plan),
        "months": r.months,
        "amount_uzs": r.amount_uzs,
        "status": r.status,
        "teacher_note": r.teacher_note,
        "admin_note": r.admin_note,
        "created_at": r.created_at,
        "decided_at": r.decided_at,
    }


@router.get("/requests")
async def list_requests(admin: CurrentAdmin, db: DB,
                        status: Literal["pending", "approved", "rejected", "all"] = "pending") -> list[dict]:
    q = select(PlanRequest).order_by(PlanRequest.created_at.desc()).limit(200)
    if status != "all":
        q = q.where(PlanRequest.status == status)
    return [_request(r) for r in await db.scalars(q)]


class DecisionIn(Schema):
    note: str | None = Field(default=None, max_length=500)


@router.post("/requests/{request_id}/{action}")
async def decide_request(request_id: uuid.UUID, action: Literal["approve", "reject"], body: DecisionIn,
                         admin: CurrentAdmin, db: DB) -> dict:
    r = await db.get(PlanRequest, request_id)
    if r is None:
        raise NotFound("REQUEST_NOT_FOUND", "So'rov topilmadi")
    if r.status != "pending":
        raise AppError("REQUEST_DECIDED", "Bu so'rov allaqachon ko'rib chiqilgan", 409)
    r.status = "approved" if action == "approve" else "rejected"
    r.admin_note = body.note
    r.decided_at = utcnow()
    r.decided_by = admin.id
    if action == "approve":
        await plans.extend_subscription(db, r.teacher_id, r.plan, r.months)
    await db.commit()
    await db.refresh(r)
    return _request(r)


# ---------------------------------------------------------------- O'qituvchilar


@router.get("/teachers")
async def list_teachers(admin: CurrentAdmin, db: DB, q: str | None = Query(None, max_length=100)) -> list[dict]:
    query = select(User).where(User.role == Role.TEACHER).order_by(User.created_at.desc()).limit(200)
    if q:
        like = f"%{q.strip()}%"
        query = query.where(or_(User.first_name.ilike(like), User.last_name.ilike(like),
                                User.email.ilike(like), User.phone.ilike(like)))
    out = []
    for t in await db.scalars(query):
        u = await plans.usage(db, t.id)
        out.append({
            "id": t.id, "name": t.full_name, "phone": t.phone, "email": t.email, "is_active": t.is_active,
            "created_at": t.created_at, "last_login_at": t.last_login_at,
            "plan": u["plan"], "status": u["status"], "ends_at": u["ends_at"], "days_left": u["days_left"],
            "groups": u["groups_used"], "students": u["students_used"],
        })
    return out


class GrantIn(Schema):
    plan_code: str = Field(max_length=32)
    months: int = Field(ge=1, le=24)


@router.post("/teachers/{teacher_id}/grant")
async def grant_plan(teacher_id: uuid.UUID, body: GrantIn, admin: CurrentAdmin, db: DB) -> dict:
    """Admin qo'lda tarif beradi (masalan naqd to'lov yoki sovg'a). Tushumga yozilmaydi."""
    teacher = await db.get(User, teacher_id)
    if teacher is None or teacher.role != Role.TEACHER:
        raise NotFound("TEACHER_NOT_FOUND", "O'qituvchi topilmadi")
    plan = await plans.get_plan(db, body.plan_code)
    if plan is None:
        raise NotFound("PLAN_NOT_FOUND", "Tarif topilmadi")
    await plans.extend_subscription(db, teacher.id, plan, body.months)
    await db.commit()
    return await plans.usage(db, teacher.id)


@router.post("/teachers/{teacher_id}/{action}")
async def toggle_teacher(teacher_id: uuid.UUID, action: Literal["block", "unblock"], admin: CurrentAdmin, db: DB) -> dict:
    teacher = await db.get(User, teacher_id)
    if teacher is None or teacher.role != Role.TEACHER:
        raise NotFound("TEACHER_NOT_FOUND", "O'qituvchi topilmadi")
    teacher.is_active = action == "unblock"
    await db.commit()
    return {"id": teacher.id, "is_active": teacher.is_active}


# ---------------------------------------------------------------- Tariflar


def _plan(p: Plan) -> dict:
    return {**plans.plan_dict(p), "id": p.id, "is_active": p.is_active, "sort_order": p.sort_order}


@router.get("/plans")
async def list_plans(admin: CurrentAdmin, db: DB) -> list[dict]:
    return [_plan(p) for p in await db.scalars(select(Plan).order_by(Plan.sort_order))]


class PlanUpdateIn(Schema):
    name: str | None = Field(default=None, min_length=2, max_length=64)
    price_uzs: int | None = Field(default=None, ge=0, le=100_000_000)
    max_groups: int | None = Field(default=None, ge=1, le=100)
    max_students: int | None = Field(default=None, ge=1, le=10_000)
    is_active: bool | None = None


@router.patch("/plans/{plan_id}")
async def update_plan(plan_id: uuid.UUID, body: PlanUpdateIn, admin: CurrentAdmin, db: DB) -> dict:
    p = await db.get(Plan, plan_id)
    if p is None:
        raise NotFound("PLAN_NOT_FOUND", "Tarif topilmadi")
    for field, value in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(p, field, value)
    await db.commit()
    await db.refresh(p)
    return _plan(p)


# ---------------------------------------------------------------- Guruhlar (qisqa ko'rinish)


@router.get("/groups")
async def list_groups(admin: CurrentAdmin, db: DB) -> list[dict]:
    rows = await db.scalars(select(Group).where(Group.status == GroupStatus.ACTIVE).order_by(Group.created_at.desc()).limit(200))
    out = []
    for g in rows:
        students = await db.scalar(select(func.count()).select_from(GroupMember).where(
            GroupMember.group_id == g.id, GroupMember.status == MemberStatus.ACTIVE))
        out.append({"id": g.id, "name": g.name, "subject": g.subject, "teacher": g.teacher.full_name,
                    "students": students, "created_at": g.created_at})
    return out


# ---------------------------------------------------------------- Murojaatlar (yordam va taklif)


def _support(m: SupportMessage) -> dict:
    u = m.user
    return {"id": m.id, "kind": m.kind, "text": m.text, "status": m.status, "admin_reply": m.admin_reply,
            "replied_at": m.replied_at, "created_at": m.created_at,
            "user": {"id": u.id, "full_name": u.full_name, "role": u.role, "email": u.email, "phone": u.phone}}


@router.get("/support")
async def list_support(admin: CurrentAdmin, db: DB,
                       status: Literal["open", "answered", "closed", "all"] = "open") -> list[dict]:
    q = select(SupportMessage).order_by(SupportMessage.created_at.desc()).limit(200)
    if status != "all":
        q = q.where(SupportMessage.status == status)
    return [_support(m) for m in await db.scalars(q)]


class SupportReplyIn(Schema):
    reply: str | None = Field(default=None, max_length=3000)
    close: bool = False


@router.post("/support/{message_id}/reply")
async def reply_support(message_id: uuid.UUID, body: SupportReplyIn, admin: CurrentAdmin, db: DB) -> dict:
    m = await db.get(SupportMessage, message_id)
    if m is None:
        raise NotFound("MESSAGE_NOT_FOUND", "Murojaat topilmadi")
    if body.reply and body.reply.strip():
        m.admin_reply = body.reply.strip()
        m.replied_at = utcnow()
        m.status = "answered"
    if body.close:
        m.status = "closed"
    await db.commit()
    await db.refresh(m)
    return _support(m)


# ---------------------------------------------------------------- Jetonlar (katalog va buyurtmalar)


def _order(o: JetonOrder) -> dict:
    return {"id": o.id, "jeton_code": o.jeton_code, "quantity": o.quantity, "amount_uzs": o.amount_uzs,
            "status": o.status, "teacher_note": o.teacher_note, "admin_note": o.admin_note,
            "created_at": o.created_at, "decided_at": o.decided_at,
            "teacher": {"id": o.teacher.id, "full_name": o.teacher.full_name, "email": o.teacher.email,
                        "phone": o.teacher.phone}}


@router.get("/jeton-orders")
async def list_jeton_orders(admin: CurrentAdmin, db: DB,
                            status: Literal["pending", "approved", "rejected", "all"] = "pending") -> list[dict]:
    q = select(JetonOrder).order_by(JetonOrder.created_at.desc()).limit(200)
    if status != "all":
        q = q.where(JetonOrder.status == status)
    return [_order(o) for o in await db.scalars(q)]


@router.post("/jeton-orders/{order_id}/{action}")
async def decide_jeton_order(order_id: uuid.UUID, action: Literal["approve", "reject"], body: DecisionIn,
                             admin: CurrentAdmin, db: DB) -> dict:
    return _order(await jetons.decide_order(db, order_id, action == "approve", body.note))


@router.get("/jetons")
async def list_jetons(admin: CurrentAdmin, db: DB) -> list[dict]:
    return [jetons.jeton_dict(j) for j in await jetons.catalog(db, active_only=False)]


class JetonUpdateIn(Schema):
    name: str | None = Field(default=None, min_length=2, max_length=64)
    description: str | None = Field(default=None, max_length=255)
    price_uzs: int | None = Field(default=None, ge=0, le=10_000_000)
    is_active: bool | None = None


@router.patch("/jetons/{code}")
async def update_jeton(code: str, body: JetonUpdateIn, admin: CurrentAdmin, db: DB) -> dict:
    j = await db.scalar(select(GiftJeton).where(GiftJeton.code == code))
    if j is None:
        raise NotFound("JETON_NOT_FOUND", "Jeton topilmadi")
    for field, value in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(j, field, value)
    await db.commit()
    await db.refresh(j)
    return jetons.jeton_dict(j)


# ---------------------------------------------------------------- Taqdimot sayti


@router.get("/site")
async def get_site(admin: CurrentAdmin, db: DB) -> dict:
    return {"economics": await site.economics(db), "downloads": await site.downloads(db),
            "secret_enabled": await site.has_secret_password(db)}


@router.put("/site/economics")
async def put_economics(body: dict, admin: CurrentAdmin, db: DB) -> dict:
    return await site.set_economics(db, body)


@router.put("/site/downloads")
async def put_downloads(body: dict, admin: CurrentAdmin, db: DB) -> dict:
    return await site.set_downloads(db, body)


class SecretPasswordIn(Schema):
    password: str = Field(min_length=6, max_length=200)


@router.put("/site/secret-password")
async def put_secret_password(body: SecretPasswordIn, admin: CurrentAdmin, db: DB) -> dict:
    await site.set_secret_password(db, body.password)
    return {"secret_enabled": True}
