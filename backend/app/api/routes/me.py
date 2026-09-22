from typing import Annotated

from fastapi import APIRouter, File, UploadFile

from app.api.deps import DB, CurrentStudent, CurrentUser
from app.api.presenters import active_edit_grant, me_out
from app.core.errors import AppError, Forbidden
from app.core.security import utcnow
from app.models import Role
from app.services.onboarding import build_ai_context
from app.services.storage import check_size, get_storage, sniff_image
from app.schemas.auth import MeOut, MeUpdateIn, StudentProfileUpdateIn

router = APIRouter(tags=["me"])


@router.get("/me", response_model=MeOut)
async def get_me(user: CurrentUser, db: DB) -> MeOut:
    return await me_out(db, user)


@router.patch("/me", response_model=MeOut)
async def update_me(body: MeUpdateIn, user: CurrentUser, db: DB) -> MeOut:
    if body.locale is not None:
        user.locale = body.locale
    if body.first_name is not None or body.last_name is not None:
        if user.role != Role.TEACHER:
            raise Forbidden("PROFILE_LOCKED", "Ma'lumotlaringizni o'zgartirish uchun ustozingiz ruxsat berishi kerak")
        user.first_name = body.first_name or user.first_name
        user.last_name = body.last_name or user.last_name
        # AI kontekstida ustoz ismi bor: yangilab qo'yamiz
        if user.teacher and user.teacher.onboarding_answers:
            user.teacher.ai_context = build_ai_context(user.full_name, user.teacher.onboarding_answers)
    await db.commit()
    return await me_out(db, user)


@router.post("/me/avatar", response_model=MeOut)
async def upload_avatar(user: CurrentUser, db: DB, file: Annotated[UploadFile, File()]) -> MeOut:
    """Profil rasmi. Telefon rasmni kvadrat va kichik (512px) qilib yuboradi; server hajm va turini tekshiradi."""
    data = await file.read()
    check_size(data, 5, "Rasm")
    _, ext = sniff_image(data)
    storage = get_storage()
    old = user.avatar_key
    user.avatar_key = storage.save(f"avatars/{user.id}", data, ext)
    await db.commit()
    if old:
        storage.delete(old)
    return await me_out(db, user)


@router.delete("/me/avatar", response_model=MeOut)
async def delete_avatar(user: CurrentUser, db: DB) -> MeOut:
    if user.avatar_key:
        get_storage().delete(user.avatar_key)
        user.avatar_key = None
        await db.commit()
    return await me_out(db, user)


@router.patch("/students/me/profile", response_model=MeOut)
async def edit_student_profile(body: StudentProfileUpdateIn, student: CurrentStudent, db: DB) -> MeOut:
    """Faqat ustoz bergan bir martalik ruxsat bilan. Saqlangach ruxsat ishlatilgan bo'ladi."""
    grant = await active_edit_grant(db, student.id)
    if grant is None:
        raise Forbidden(
            "PROFILE_LOCKED", "Ma'lumotlarni o'zgartirish uchun ustozingiz ruxsat berishi kerak"
        )
    changes = body.model_dump(exclude_unset=True, exclude_none=True)
    if not changes:
        raise AppError("NOTHING_TO_UPDATE", "O'zgartirish kiritilmadi")

    profile = student.student
    diff: dict[str, dict[str, str | None]] = {}
    for field, value in changes.items():
        target = profile if field in ("birth_date", "gender") else student
        old = getattr(target, field)
        if old != value:
            diff[field] = {"old": str(old) if old is not None else None, "new": str(value)}
            setattr(target, field, value)

    grant.used_at = utcnow()
    grant.changes = diff
    await db.commit()
    await db.refresh(student)
    return await me_out(db, student)
