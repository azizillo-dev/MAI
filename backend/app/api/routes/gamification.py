import uuid
from typing import Literal

from fastapi import APIRouter, Query
from sqlalchemy import select

from app.api.deps import DB, CurrentStudent, CurrentUser
from app.core.errors import NotFound
from app.models import Group, GroupMember, GroupStatus, MemberStatus, Role
from app.services import gamification as gm
from app.services.student_profile import student_card

router = APIRouter(tags=["gamification"])


@router.get("/students/me/progress")
async def my_progress(student: CurrentStudent, db: DB) -> dict:
    """XP, daraja, nishonlar (olingan/olinmagan + progress), oylik medallar, guruhdagi o'rin."""
    return await gm.student_progress(db, student)


@router.get("/students/{student_id}/profile")
async def student_profile(student_id: uuid.UUID, user: CurrentUser, db: DB) -> dict:
    """O'quvchi profili: XP, daraja, nishonlar, reyting. Ustozga qo'shimcha: ishlar ro'yxati va aloqa."""
    return await student_card(db, user, student_id)


@router.get("/leaderboard")
async def leaderboard(
    user: CurrentUser,
    db: DB,
    group_id: uuid.UUID,
    scope: Literal["group", "teacher"] = "group",
    period: Literal["month", "3months", "all"] = "month",
) -> dict:
    """Reyting. O'quvchi faqat o'z guruhini yoki shu ustozning barcha o'quvchilari orasidagi o'rnini ko'radi."""
    group = await db.get(Group, group_id)
    if group is None or group.status != GroupStatus.ACTIVE:
        raise NotFound("GROUP_NOT_FOUND", "Guruh topilmadi")
    if user.role == Role.TEACHER:
        allowed = group.teacher_id == user.id
    else:
        allowed = bool(await db.scalar(select(GroupMember.id).where(
            GroupMember.group_id == group.id, GroupMember.student_id == user.id,
            GroupMember.status == MemberStatus.ACTIVE,
        )))
    if not allowed:
        raise NotFound("GROUP_NOT_FOUND", "Guruh topilmadi")

    await gm.award_monthly_medals(db, group)
    rows = await gm.leaderboard(db, group, scope, period)
    me = next((r for r in rows if r["student_id"] == user.id), None)
    return {
        "group_id": group.id,
        "group_name": group.name,
        "teacher_name": group.teacher.full_name,
        "scope": scope,
        "period": period,
        "entries": rows,
        "me": me,
    }
