"""Model -> javob sxemasi. Bir joyda turgani uchun barcha endpoint'lar bir xil ma'lumot qaytaradi."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import utcnow
from app.models import Group, GroupMember, ProfileEditGrant, Role, User
from app.schemas.auth import MeOut, StudentInfo, TeacherInfo
from app.schemas.groups import MemberOut, MembershipOut, TeacherBrief, TeacherGroupOut
from app.services.groups import format_code, invite_url
from app.services.storage import signed_url


def avatar_url(user: User) -> str | None:
    return signed_url(user.avatar_key) if user.avatar_key else None


async def active_edit_grant(db: AsyncSession, student_id) -> ProfileEditGrant | None:
    return await db.scalar(
        select(ProfileEditGrant)
        .where(
            ProfileEditGrant.student_id == student_id,
            ProfileEditGrant.used_at.is_(None),
            ProfileEditGrant.expires_at > utcnow(),
        )
        .order_by(ProfileEditGrant.created_at.desc())
        .limit(1)
    )


async def me_out(db: AsyncSession, user: User) -> MeOut:
    student = teacher = None
    next_step = "home"
    if user.role == Role.STUDENT and user.student:
        student = StudentInfo(
            birth_date=user.student.birth_date,
            gender=user.student.gender,
            is_locked=user.student.is_locked,
            can_edit=await active_edit_grant(db, user.id) is not None,
        )
    if user.role == Role.TEACHER and user.teacher:
        done = user.teacher.onboarding_completed_at is not None
        teacher = TeacherInfo(onboarding_completed=done, default_grading_scale=user.teacher.default_grading_scale)
        if not done:
            next_step = "teacher_onboarding"
    return MeOut(
        id=user.id,
        phone=user.phone,
        email=user.email,
        role=user.role,
        first_name=user.first_name,
        last_name=user.last_name,
        middle_name=user.middle_name,
        full_name=user.full_name,
        locale=user.locale,
        avatar_url=avatar_url(user),
        student=student,
        teacher=teacher,
        next_step=next_step,
    )


def teacher_group_out(group: Group, counts: dict[str, int]) -> TeacherGroupOut:
    return TeacherGroupOut(
        id=group.id,
        name=group.name,
        subject=group.subject,
        grading_scale=group.grading_scale,
        status=group.status,
        join_enabled=group.join_enabled,
        join_code=format_code(group.join_code),
        join_password=group.join_password,
        invite_url=invite_url(group),
        members_active=counts.get("active", 0),
        members_pending=counts.get("pending", 0),
        created_at=group.created_at,
    )


def membership_out(m: GroupMember) -> MembershipOut:
    g = m.group
    return MembershipOut(
        group_id=g.id,
        group_name=g.name,
        subject=g.subject,
        grading_scale=g.grading_scale,
        teacher=TeacherBrief(id=g.teacher.id, full_name=g.teacher.full_name, avatar_url=avatar_url(g.teacher)),
        status=m.status,
        requested_at=m.created_at,
        decided_at=m.decided_at,
    )


def member_out(m: GroupMember) -> MemberOut:
    s = m.student
    return MemberOut(
        student_id=s.id,
        first_name=s.first_name,
        last_name=s.last_name,
        full_name=s.full_name,
        phone=s.phone,
        email=s.email,
        avatar_url=avatar_url(s),
        status=m.status,
        requested_at=m.created_at,
        decided_at=m.decided_at,
    )
