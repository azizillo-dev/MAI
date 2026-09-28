"""O'qituvchi dashboard'i: bitta so'rov bilan bosh sahifa uchun hamma narsa."""

import uuid
from datetime import timedelta

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import as_utc, utcnow
from app.models import (
    Assignment,
    AssignmentStatus,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    Submission,
    SubmissionStatus,
    User,
)
from app.services.analytics import teacher_analytics
from app.services.assignments import TASHKENT, week_start_utc


async def teacher_dashboard(db: AsyncSession, teacher_id: uuid.UUID) -> dict:
    now = utcnow()
    week_start = week_start_utc(now)
    active_group = and_(Group.teacher_id == teacher_id, Group.status == GroupStatus.ACTIVE)

    groups = await db.scalar(select(func.count()).select_from(Group).where(active_group))
    students = await db.scalar(
        select(func.count(func.distinct(GroupMember.student_id)))
        .join(Group, Group.id == GroupMember.group_id)
        .where(active_group, GroupMember.status == MemberStatus.ACTIVE)
    )
    pending_requests = await db.scalar(
        select(func.count())
        .select_from(GroupMember)
        .join(Group, Group.id == GroupMember.group_id)
        .where(active_group, GroupMember.status == MemberStatus.PENDING)
    )
    to_review = await db.scalar(
        select(func.count())
        .select_from(Submission)
        .join(Assignment, Assignment.id == Submission.assignment_id)
        .where(
            Assignment.teacher_id == teacher_id,
            Submission.status.in_([SubmissionStatus.NEEDS_REVIEW, SubmissionStatus.FAILED]),
        )
    )
    drafts = await db.scalar(
        select(func.count())
        .select_from(Assignment)
        .where(
            Assignment.teacher_id == teacher_id,
            Assignment.status.in_([AssignmentStatus.REVIEW, AssignmentStatus.FAILED]),
        )
    )

    # Hozir ochiq (muddati o'tmagan) nashr qilingan vazifalar. Faqat kerakli ustunlar:
    # to'liq obyekt (rasmlari, guruhi, ustozi bilan) bosh sahifa uchun ortiqcha
    open_assignments = (await db.execute(
        select(Assignment.id, Assignment.title, Assignment.group_id, Assignment.due_at, Group.name.label("group_name"))
        .join(Group, Group.id == Assignment.group_id)
        .where(
            Assignment.teacher_id == teacher_id,
            Assignment.status == AssignmentStatus.PUBLISHED,
            Assignment.due_at >= now,
        )
        .order_by(Assignment.due_at)
    )).all()

    top = open_assignments[:5]
    submitted_by: dict = {}
    members_by: dict = {}
    if top:
        submitted_by = dict((await db.execute(
            select(Submission.assignment_id, func.count())
            .where(Submission.assignment_id.in_([a.id for a in top]))
            .group_by(Submission.assignment_id)
        )).all())
        members_by = dict((await db.execute(
            select(GroupMember.group_id, func.count())
            .where(GroupMember.group_id.in_({a.group_id for a in top}), GroupMember.status == MemberStatus.ACTIVE)
            .group_by(GroupMember.group_id)
        )).all())

    upcoming = []
    for a in top:
        submitted, members = submitted_by.get(a.id, 0), members_by.get(a.group_id, 0)
        upcoming.append(
            {
                "assignment_id": a.id,
                "title": a.title,
                "group_name": a.group_name,
                "due_at": a.due_at,
                "submitted": submitted,
                "members": members,
            }
        )

    # Shu haftada baholangan ishlar: o'rtacha natija va topshirish ko'rsatkichi
    week_rows = (await db.execute(
        select(Submission.final_score, Group.grading_scale)
        .join(Assignment, Assignment.id == Submission.assignment_id)
        .join(Group, Group.id == Assignment.group_id)
        .where(
            Assignment.teacher_id == teacher_id,
            Submission.status == SubmissionStatus.GRADED,
            Submission.submitted_at >= week_start,
        )
    )).all()
    percents = [round(score / float(scale) * 100, 1) for score, scale in week_rows if score is not None and float(scale)]

    # Oxirgi 7 kun: har kuni nechta ish topshirildi (grafik uchun, Toshkent kunlari)
    since = (now.astimezone(TASHKENT) - timedelta(days=6)).replace(hour=0, minute=0, second=0, microsecond=0)
    recent_times = list(
        await db.scalars(
            select(Submission.submitted_at)
            .join(Assignment, Assignment.id == Submission.assignment_id)
            .where(Assignment.teacher_id == teacher_id, Submission.submitted_at >= since)
        )
    )
    per_day = {(since + timedelta(days=i)).date(): 0 for i in range(7)}
    for t in recent_times:
        day = as_utc(t).astimezone(TASHKENT).date()
        if day in per_day:
            per_day[day] += 1

    recent = (await db.execute(
        select(Submission.id, User.first_name, User.last_name, Assignment.title, Submission.status,
               Submission.final_score, Group.grading_scale, Submission.submitted_at)
        .join(Assignment, Assignment.id == Submission.assignment_id)
        .join(Group, Group.id == Assignment.group_id)
        .join(User, User.id == Submission.student_id)
        .where(Assignment.teacher_id == teacher_id, Submission.status != SubmissionStatus.GRADING)
        .order_by(Submission.submitted_at.desc())
        .limit(6)
    )).all()

    return {
        "analytics": await teacher_analytics(db, teacher_id),
        "stats": {
            "groups": groups,
            "students": students,
            "pending_requests": pending_requests,
            "open_assignments": len(open_assignments),
            "drafts": drafts,
            "to_review": to_review,
            "graded_this_week": len(week_rows),
            "avg_percent_week": round(sum(percents) / len(percents), 1) if percents else None,
        },
        "upcoming": upcoming,
        "activity": [{"day": d.isoformat(), "count": c} for d, c in per_day.items()],
        "recent": [
            {
                "submission_id": r.id,
                "student_name": f"{r.first_name} {r.last_name}",
                "assignment_title": r.title,
                "status": r.status,
                "final_score": r.final_score,
                "grading_scale": r.grading_scale,
                "submitted_at": r.submitted_at,
            }
            for r in recent
        ],
    }
