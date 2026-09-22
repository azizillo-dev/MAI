"""O'quvchi profili boshqalar nazarida: ustoz (to'liq) va guruhdoshlar (ommaviy qism).

Kim ko'ra oladi:
- ustoz: o'quvchi uning biror guruhida (faol yoki so'rov yuborgan) bo'lsa;
- o'quvchi: o'zini, yoki shu ustozda o'qiydigan boshqa o'quvchini (reytingdagi kabi).
Topshirilgan ishlar, baholar ro'yxati va aloqa ma'lumotlari faqat ustozga ko'rinadi.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.presenters import avatar_url
from app.core.errors import NotFound
from app.core.security import as_utc, utcnow
from app.models import (
    Assignment,
    AssignmentStatus,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    Role,
    Submission,
    SubmissionStatus,
    User,
)
from app.services import gamification as gm


async def _active_groups(db: AsyncSession, student_id: uuid.UUID, statuses=(MemberStatus.ACTIVE,)) -> list[Group]:
    return list(await db.scalars(
        select(Group).join(GroupMember, GroupMember.group_id == Group.id).where(
            GroupMember.student_id == student_id,
            GroupMember.status.in_(statuses),
            Group.status == GroupStatus.ACTIVE,
        )
    ))


async def _visible_groups(db: AsyncSession, viewer: User, student: User) -> list[Group] | None:
    """Ko'ruvchiga tegishli guruhlar (reyting va ishlar shu doirada). None — ruxsat yo'q."""
    if viewer.role == Role.TEACHER:
        groups = [g for g in await _active_groups(db, student.id, (MemberStatus.ACTIVE, MemberStatus.PENDING))
                  if g.teacher_id == viewer.id]
        return groups or None
    if viewer.role != Role.STUDENT:
        return None
    target_groups = await _active_groups(db, student.id)
    if viewer.id == student.id:
        return target_groups
    viewer_teachers = {g.teacher_id for g in await _active_groups(db, viewer.id)}
    groups = [g for g in target_groups if g.teacher_id in viewer_teachers]
    return groups or None


async def student_card(db: AsyncSession, viewer: User, student_id: uuid.UUID) -> dict:
    student = await db.get(User, student_id)
    if student is None or student.role != Role.STUDENT or not student.is_active:
        raise NotFound("STUDENT_NOT_FOUND", "O'quvchi topilmadi")
    groups = await _visible_groups(db, viewer, student)
    if groups is None:
        raise NotFound("STUDENT_NOT_FOUND", "O'quvchi topilmadi")

    progress = await gm.student_progress(db, student)
    group_ids = {g.id for g in groups}
    out: dict = {
        "id": student.id,
        "first_name": student.first_name,
        "last_name": student.last_name,
        "full_name": student.full_name,
        "avatar_url": avatar_url(student),
        "joined_at": student.created_at,
        "is_self": viewer.id == student.id,
        "xp": progress["xp"],
        "level": progress["level"],
        "level_name": progress["level_name"],
        "level_xp": progress["level_xp"],
        "level_span": progress["level_span"],
        "stats": progress["stats"],
        "ranks": [r for r in progress["ranks"] if r["group_id"] in group_ids],
        "groups": [{"id": g.id, "name": g.name, "subject": g.subject} for g in groups],
        # Ommaviy qism: faqat olingan nishonlar (to'liq katalog o'quvchining o'z sahifasida)
        "badges": [b for b in progress["badges"] if b["earned_at"]],
        "medals": progress["medals"],
        "gifts": progress["gifts"],
        "teacher_view": None,
    }
    if viewer.role == Role.TEACHER:
        out["teacher_view"] = await _teacher_details(db, student, groups)
    return out


async def _teacher_details(db: AsyncSession, student: User, groups: list[Group]) -> dict:
    group_ids = [g.id for g in groups]
    subs = list(await db.scalars(
        select(Submission).join(Assignment, Assignment.id == Submission.assignment_id)
        .where(Submission.student_id == student.id, Assignment.group_id.in_(group_ids))
        .order_by(Submission.submitted_at.desc())
    ))
    submitted_ids = {s.assignment_id for s in subs}
    now = utcnow()
    published = list(await db.scalars(
        select(Assignment).where(
            Assignment.group_id.in_(group_ids), Assignment.status == AssignmentStatus.PUBLISHED,
        ).order_by(Assignment.due_at.desc())
    ))
    missing = [a for a in published if a.id not in submitted_ids and as_utc(a.due_at) < now]
    open_ = [a for a in published if a.id not in submitted_ids and as_utc(a.due_at) >= now]

    def pct(s: Submission) -> float | None:
        return round(gm._percent(s), 1) if s.status == SubmissionStatus.GRADED and s.final_score is not None else None

    graded = [p for s in subs if (p := pct(s)) is not None]
    p = student.student
    return {
        "phone": student.phone,
        "email": student.email,
        "birth_date": p.birth_date if p else None,
        "summary": {
            "assigned": len(published),
            "submitted": len(subs),
            "missing": len(missing),
            "late": sum(1 for s in subs if s.is_late),
            "avg_percent": round(sum(graded) / len(graded), 1) if graded else None,
            "waiting_review": sum(1 for s in subs if s.status in (SubmissionStatus.NEEDS_REVIEW, SubmissionStatus.FAILED)),
        },
        "submissions": [
            {
                "id": s.id,
                "assignment_id": s.assignment_id,
                "title": s.assignment.title,
                "group_name": s.assignment.group.name,
                "status": s.status,
                "final_score": s.final_score,
                "grading_scale": s.assignment.group.grading_scale,
                "percent": pct(s),
                "is_late": s.is_late,
                "submitted_at": s.submitted_at,
            }
            for s in subs
        ],
        "missing": [
            {"assignment_id": a.id, "title": a.title, "group_name": a.group.name, "due_at": a.due_at} for a in missing
        ],
        "open": [
            {"assignment_id": a.id, "title": a.title, "group_name": a.group.name, "due_at": a.due_at} for a in open_
        ],
    }
