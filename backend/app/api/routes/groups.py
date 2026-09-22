import uuid
from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Query
from sqlalchemy import select

from app.api.deps import DB, CurrentStudent, CurrentTeacher
from app.api.presenters import member_out, membership_out, teacher_group_out
from app.core.errors import Conflict, Forbidden, NotFound
from app.core.security import utcnow
from app.models import Group, GroupMember, GroupStatus, MemberStatus, ProfileEditGrant
from app.schemas.common import Message
from app.schemas.groups import (
    ApproveAllOut,
    GroupCreateIn,
    GroupUpdateIn,
    JoinIn,
    JoinPreviewIn,
    JoinPreviewOut,
    JoinToggleIn,
    MemberOut,
    MembershipOut,
    TeacherGroupOut,
)
from app.services import groups as svc
from app.services import plans

router = APIRouter(tags=["groups"])

# ---------------------------------------------------------------- O'qituvchi


@router.post("/groups", response_model=TeacherGroupOut, status_code=201)
async def create_group(body: GroupCreateIn, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    if teacher.teacher.onboarding_completed_at is None:
        raise Forbidden("ONBOARDING_REQUIRED", "Avval bir nechta savolga javob bering")
    group = await svc.create_group(db, teacher, body.name, body.subject, body.grading_scale)
    return teacher_group_out(group, {})


@router.get("/groups", response_model=list[TeacherGroupOut])
async def list_groups(
    teacher: CurrentTeacher, db: DB, status: Literal["active", "archived"] = "active"
) -> list[TeacherGroupOut]:
    rows = list(
        await db.scalars(
            select(Group).where(Group.teacher_id == teacher.id, Group.status == status).order_by(Group.created_at)
        )
    )
    counts = await svc.member_counts(db, [g.id for g in rows])
    return [teacher_group_out(g, counts[g.id]) for g in rows]


@router.get("/groups/{group_id}", response_model=TeacherGroupOut)
async def get_group(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    group = await svc.get_teacher_group(db, teacher, group_id)
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.patch("/groups/{group_id}", response_model=TeacherGroupOut)
async def update_group(group_id: uuid.UUID, body: GroupUpdateIn, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    group = await svc.get_teacher_group(db, teacher, group_id)
    for field, value in body.model_dump(exclude_unset=True, exclude_none=True).items():
        setattr(group, field, value)
    await db.commit()
    await db.refresh(group)
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.post("/groups/{group_id}/rotate-credentials", response_model=TeacherGroupOut)
async def rotate_credentials(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    """Yangi parol va taklif havolasi. Eski parol/QR/havola darhol ishlamay qoladi, a'zolar esa guruhda qoladi."""
    group = await svc.rotate_credentials(db, await svc.get_teacher_group(db, teacher, group_id))
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.post("/groups/{group_id}/join-status", response_model=TeacherGroupOut)
async def set_join_status(group_id: uuid.UUID, body: JoinToggleIn, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    """Qo'shilishni yopish/ochish. Yopiq bo'lsa kod, QR va havola ishlamaydi; guruhdagilar qoladi."""
    group = await svc.set_join_enabled(db, await svc.get_teacher_group(db, teacher, group_id), body.enabled)
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.post("/groups/{group_id}/members/approve-all", response_model=ApproveAllOut)
async def approve_all(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> ApproveAllOut:
    """Kutayotganlarning hammasini tarif limiti yetguncha qabul qiladi."""
    group = await svc.get_teacher_group(db, teacher, group_id)
    return ApproveAllOut(**await svc.approve_all(db, group))


@router.post("/groups/{group_id}/archive", response_model=TeacherGroupOut)
async def archive_group(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    group = await svc.get_teacher_group(db, teacher, group_id)
    group.status = GroupStatus.ARCHIVED
    await db.commit()
    await db.refresh(group)
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.post("/groups/{group_id}/restore", response_model=TeacherGroupOut)
async def restore_group(group_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> TeacherGroupOut:
    group = await svc.get_teacher_group(db, teacher, group_id)
    if group.status != GroupStatus.ACTIVE:
        plan = await plans.require_plan(db, teacher.id)
        if await plans.active_group_count(db, teacher.id) >= plan.max_groups:
            raise Forbidden(
                "PLAN_GROUP_LIMIT",
                f"{plan.name} tarifida {plan.max_groups} ta faol guruh bo'lishi mumkin",
                details={"limit": plan.max_groups, "plan": plan.code},
            )
        group.status = GroupStatus.ACTIVE
        await db.commit()
        await db.refresh(group)
    return teacher_group_out(group, (await svc.member_counts(db, [group.id]))[group.id])


@router.get("/groups/{group_id}/members", response_model=list[MemberOut])
async def list_members(
    group_id: uuid.UUID,
    teacher: CurrentTeacher,
    db: DB,
    status: Literal["active", "pending"] | None = Query(None),
) -> list[MemberOut]:
    group = await svc.get_teacher_group(db, teacher, group_id)
    q = select(GroupMember).where(GroupMember.group_id == group.id)
    q = q.where(GroupMember.status == status) if status else q.where(
        GroupMember.status.in_([MemberStatus.ACTIVE, MemberStatus.PENDING])
    )
    members = list(await db.scalars(q))
    # Kutayotganlar tepada, keyin familiya bo'yicha
    members.sort(key=lambda m: (m.status != MemberStatus.PENDING, m.student.last_name, m.student.first_name))
    return [member_out(m) for m in members]


@router.post("/groups/{group_id}/members/{student_id}/grant-profile-edit", response_model=Message)
async def grant_profile_edit(group_id: uuid.UUID, student_id: uuid.UUID, teacher: CurrentTeacher, db: DB) -> Message:
    """O'quvchiga profilini 1 marta tahrirlash imkonini beradi (7 kun amal qiladi)."""
    await svc.get_teacher_group(db, teacher, group_id)
    member = await db.scalar(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.student_id == student_id,
            GroupMember.status == MemberStatus.ACTIVE,
        )
    )
    if member is None:
        raise NotFound("MEMBER_NOT_FOUND", "O'quvchi topilmadi")
    now = utcnow()
    existing = await db.scalar(
        select(ProfileEditGrant.id).where(
            ProfileEditGrant.student_id == student_id,
            ProfileEditGrant.used_at.is_(None),
            ProfileEditGrant.expires_at > now,
        )
    )
    if existing:
        raise Conflict("GRANT_EXISTS", "O'quvchida tahrirlash ruxsati allaqachon ochiq")
    db.add(
        ProfileEditGrant(student_id=student_id, teacher_id=teacher.id, created_at=now, expires_at=now + timedelta(days=7))
    )
    await db.commit()
    return Message(message="Ruxsat berildi. O'quvchi ma'lumotlarini bir marta o'zgartira oladi")


@router.post("/groups/{group_id}/members/{student_id}/{action}", response_model=MemberOut)
async def decide_member(
    group_id: uuid.UUID,
    student_id: uuid.UUID,
    action: Literal["approve", "reject", "remove"],
    teacher: CurrentTeacher,
    db: DB,
) -> MemberOut:
    group = await svc.get_teacher_group(db, teacher, group_id)
    return member_out(await svc.decide_member(db, group, student_id, action))


# ---------------------------------------------------------------- O'quvchi


@router.get("/memberships", response_model=list[MembershipOut])
async def my_memberships(student: CurrentStudent, db: DB) -> list[MembershipOut]:
    rows = await db.scalars(
        select(GroupMember)
        .join(Group, Group.id == GroupMember.group_id)
        .where(
            GroupMember.student_id == student.id,
            GroupMember.status.in_([MemberStatus.ACTIVE, MemberStatus.PENDING]),
            Group.status == GroupStatus.ACTIVE,
        )
        .order_by(GroupMember.created_at)
    )
    return [membership_out(m) for m in rows]


@router.post("/memberships/preview", response_model=JoinPreviewOut)
async def preview_group(body: JoinPreviewIn, student: CurrentStudent, db: DB) -> JoinPreviewOut:
    """Parol kiritishdan oldin o'quvchi to'g'ri guruhga qo'shilayotganini ko'radi."""
    group = await svc.find_joinable_group(db, body.code)
    counts = (await svc.member_counts(db, [group.id]))[group.id]
    return JoinPreviewOut(
        code=svc.format_code(group.join_code),
        group_name=group.name,
        subject=group.subject,
        teacher_name=group.teacher.full_name,
        members_active=counts["active"],
    )


@router.post("/memberships", response_model=MembershipOut, status_code=201)
async def join_group(body: JoinIn, student: CurrentStudent, db: DB) -> MembershipOut:
    member = await svc.join_group(db, student, body.code, body.password, body.invite_token)
    return membership_out(member)


@router.delete("/memberships/{group_id}", response_model=Message)
async def leave_group(group_id: uuid.UUID, student: CurrentStudent, db: DB) -> Message:
    """Kutilayotgan so'rovni bekor qilish yoki guruhdan chiqish."""
    member = await db.scalar(
        select(GroupMember).where(GroupMember.group_id == group_id, GroupMember.student_id == student.id)
    )
    if member is None or member.status not in (MemberStatus.ACTIVE, MemberStatus.PENDING):
        raise NotFound("MEMBER_NOT_FOUND", "Siz bu guruhda emassiz")
    member.status = MemberStatus.REMOVED
    member.decided_at = utcnow()
    await db.commit()
    return Message()
