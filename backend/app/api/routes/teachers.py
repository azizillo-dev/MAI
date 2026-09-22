from typing import Literal

from fastapi import APIRouter, Query
from pydantic import Field

from app.api.deps import DB, CurrentTeacher
from app.core.security import utcnow
from app.schemas.groups import OnboardingIn, OnboardingOut, PlanUsageOut
from app.ai.assistant import get_assistant
from app.ai.provider import AiError
from app.core.errors import AppError
from app.schemas.common import Schema
from sqlalchemy import select

from app.models import Plan, PlanRequest
from app.services import onboarding, plans
from app.services.assistant_tools import AssistantTools
from app.services.dashboard import teacher_dashboard

router = APIRouter(prefix="/teachers", tags=["teachers"])


@router.get("/onboarding/questions")
async def onboarding_questions(lang: str = Query("uz", max_length=8)) -> dict:
    return {"questions": onboarding.localized_questions(lang)}


@router.get("/me/onboarding", response_model=OnboardingOut)
async def get_onboarding(teacher: CurrentTeacher) -> OnboardingOut:
    p = teacher.teacher
    return OnboardingOut(
        answers=p.onboarding_answers or {}, ai_context=p.ai_context or "", completed_at=p.onboarding_completed_at
    )


@router.put("/me/onboarding", response_model=OnboardingOut)
async def save_onboarding(body: OnboardingIn, teacher: CurrentTeacher, db: DB) -> OnboardingOut:
    """Birinchi marta ham, keyin sozlamalardan tahrirlashda ham shu endpoint ishlatiladi."""
    answers = onboarding.validate_answers(body.answers)
    p = teacher.teacher
    p.onboarding_answers = answers
    p.ai_context = onboarding.build_ai_context(teacher.full_name, answers)
    p.default_grading_scale = answers["grading_scale"]
    if p.onboarding_completed_at is None:
        p.onboarding_completed_at = utcnow()
    await db.commit()
    return OnboardingOut(answers=answers, ai_context=p.ai_context, completed_at=p.onboarding_completed_at)


@router.get("/me/dashboard")
async def dashboard(teacher: CurrentTeacher, db: DB) -> dict:
    return await teacher_dashboard(db, teacher.id)


class ChatMessage(Schema):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class AssistantIn(Schema):
    # Suhbat tarixi ilovada saqlanadi; oxirgi 12 xabar yuboriladi
    messages: list[ChatMessage] = Field(min_length=1, max_length=20)


@router.post("/me/assistant")
async def assistant(body: AssistantIn, teacher: CurrentTeacher, db: DB) -> dict:
    """AI yordamchi: o'quvchi va guruhlar haqidagi savollarga aniq raqamlar bilan javob."""
    history = [m.model_dump() for m in body.messages[-12:]]
    if history[-1]["role"] != "user":
        raise AppError("LAST_MESSAGE_NOT_USER", "Oxirgi xabar savol bo'lishi kerak", 422)
    tools = AssistantTools(db, teacher)
    try:
        r = await get_assistant().reply(tools, history)
    except AiError as exc:
        raise AppError("AI_UNAVAILABLE", str(exc), 503) from exc
    return {"reply": r.text, "attachments": r.attachments, "tools": r.tool_calls}


@router.get("/plans")
async def list_plans(teacher: CurrentTeacher, db: DB) -> dict:
    """Sotib olinadigan tariflar (sinovdan tashqari) va o'qituvchining so'rovlari."""
    rows = await db.scalars(select(Plan).where(Plan.is_active.is_(True), Plan.code != plans.TRIAL).order_by(Plan.sort_order))
    requests = await db.scalars(
        select(PlanRequest).where(PlanRequest.teacher_id == teacher.id).order_by(PlanRequest.created_at.desc()).limit(10)
    )
    return {
        "plans": [plans.plan_dict(p) for p in rows],
        "requests": [_request_out(r) for r in requests],
    }


class PlanRequestIn(Schema):
    plan_code: str = Field(max_length=32)
    months: int = Field(ge=1, le=12)
    note: str | None = Field(default=None, max_length=500)


def _request_out(r: PlanRequest) -> dict:
    return {
        "id": r.id, "plan": plans.plan_dict(r.plan), "months": r.months, "amount_uzs": r.amount_uzs,
        "status": r.status, "admin_note": r.admin_note, "created_at": r.created_at, "decided_at": r.decided_at,
    }


@router.post("/me/plan-requests", status_code=201)
async def request_plan(body: PlanRequestIn, teacher: CurrentTeacher, db: DB) -> dict:
    """Tarifga so'rov: admin to'lovni tasdiqlagach tarif darhol yoqiladi."""
    plan = await plans.get_plan(db, body.plan_code)
    if plan is None or not plan.is_active or plan.code == plans.TRIAL:
        raise AppError("PLAN_NOT_FOUND", "Bunday tarif yo'q", 404)
    pending = await db.scalar(select(PlanRequest.id).where(
        PlanRequest.teacher_id == teacher.id, PlanRequest.status == "pending"))
    if pending:
        raise AppError("REQUEST_PENDING", "Oldingi so'rovingiz ko'rib chiqilmoqda. Admin tez orada bog'lanadi", 409)
    r = PlanRequest(teacher_id=teacher.id, plan_id=plan.id, months=body.months,
                    amount_uzs=plan.price_uzs * body.months, teacher_note=body.note)
    db.add(r)
    await db.commit()
    await db.refresh(r)
    return _request_out(r)


@router.get("/me/plan", response_model=PlanUsageOut)
async def my_plan(teacher: CurrentTeacher, db: DB) -> PlanUsageOut:
    return PlanUsageOut(**await plans.usage(db, teacher.id))
