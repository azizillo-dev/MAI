"""O'qituvchi dashboardi uchun guruhlar tahlili.

Faqat kerakli ustunlar o'qiladi (to'liq obyektlar yuklanmaydi) va natija qisqa muddat keshlanadi:
dashboard tez-tez ochiladi, tahlil esa daqiqasiga bir necha marta o'zgarmaydi.
"""

import uuid
from collections import defaultdict
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import TTLCache
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
)
from app.services.assignments import TASHKENT

WEEKS = 8
LOW_PERCENT = 60
_cache = TTLCache(60)


def _bucket(p: float) -> str:
    # Maktabdagi odatiy chegaralar: a'lo / yaxshi / qoniqarli / qoniqarsiz
    return "excellent" if p >= 86 else "good" if p >= 71 else "fair" if p >= 51 else "poor"


def _week_start(dt) -> str:
    local = as_utc(dt).astimezone(TASHKENT)
    return (local - timedelta(days=local.weekday())).date().isoformat()


async def teacher_analytics(db: AsyncSession, teacher_id: uuid.UUID) -> dict:
    cached = _cache.get(teacher_id)
    if cached is not None:
        return cached
    out = await _compute(db, teacher_id)
    _cache.set(teacher_id, out)
    return out


def invalidate(teacher_id: uuid.UUID) -> None:
    _cache.invalidate(lambda k: k == teacher_id)


async def _compute(db: AsyncSession, teacher_id: uuid.UUID) -> dict:
    groups = (await db.execute(
        select(Group.id, Group.name, Group.subject)
        .where(Group.teacher_id == teacher_id, Group.status == GroupStatus.ACTIVE)
        .order_by(Group.created_at)
    )).all()
    if not groups:
        return {"groups": [], "distribution": {}, "weeks": []}
    gids = [g.id for g in groups]

    members = dict((await db.execute(
        select(GroupMember.group_id, func.count())
        .where(GroupMember.group_id.in_(gids), GroupMember.status == MemberStatus.ACTIVE)
        .group_by(GroupMember.group_id)
    )).all())
    assignments = (await db.execute(
        select(Assignment.id, Assignment.group_id, Assignment.title, Assignment.items, Assignment.due_at)
        .where(Assignment.group_id.in_(gids), Assignment.status == AssignmentStatus.PUBLISHED)
    )).all()
    by_assignment = {a.id: a for a in assignments}

    since = utcnow() - timedelta(weeks=WEEKS)
    subs = (await db.execute(
        select(Submission.assignment_id, Submission.student_id, Submission.final_score, Submission.submitted_at,
               Submission.ai_items, Group.grading_scale)
        .join(Assignment, Assignment.id == Submission.assignment_id)
        .join(Group, Group.id == Assignment.group_id)
        .where(Assignment.group_id.in_(gids), Submission.status == SubmissionStatus.GRADED)
    )).all()

    weeks = [(utcnow() - timedelta(weeks=i)) for i in range(WEEKS - 1, -1, -1)]
    week_keys = [_week_start(w) for w in weeks]
    per_group: dict = {g.id: {"percents": [], "by_student": defaultdict(list), "by_assignment": defaultdict(list),
                              "weekly": defaultdict(list), "items": {}} for g in groups}
    distribution = {"excellent": 0, "good": 0, "fair": 0, "poor": 0}

    for s in subs:
        a = by_assignment.get(s.assignment_id)
        if a is None or s.final_score is None or not float(s.grading_scale):
            continue
        pct = s.final_score / float(s.grading_scale) * 100
        pg = per_group[a.group_id]
        pg["percents"].append(pct)
        pg["by_student"][s.student_id].append(pct)
        pg["by_assignment"][a.id].append(pct)
        if as_utc(s.submitted_at) >= since:
            pg["weekly"][_week_start(s.submitted_at)].append(pct)
            distribution[_bucket(pct)] += 1
        texts = {str(i.get("number")): i.get("text") for i in (a.items or [])}
        for it in s.ai_items or []:
            key = (a.id, str(it.get("number")))
            st = pg["items"].setdefault(key, {"assignment": a.title, "number": key[1],
                                              "text": (texts.get(key[1]) or "")[:120], "total": 0, "wrong": 0})
            st["total"] += 1
            if it.get("verdict") in ("incorrect", "partial", "missing"):
                st["wrong"] += 1

    result = []
    for g in groups:
        pg = per_group[g.id]
        avgs = {aid: sum(v) / len(v) for aid, v in pg["by_assignment"].items() if len(v) >= 2}
        hardest = min(avgs.items(), key=lambda kv: kv[1]) if avgs else None
        items = [v for v in pg["items"].values() if v["total"] >= 3 and v["wrong"]]
        top_mistake = max(items, key=lambda v: (v["wrong"] / v["total"], v["total"])) if items else None
        student_avgs = [sum(v) / len(v) for v in pg["by_student"].values()]
        result.append({
            "group_id": g.id,
            "name": g.name,
            "subject": g.subject,
            "students": members.get(g.id, 0),
            "assignments": sum(1 for a in assignments if a.group_id == g.id),
            "checked": len(pg["percents"]),
            "avg_percent": round(sum(pg["percents"]) / len(pg["percents"]), 1) if pg["percents"] else None,
            "low_performers": sum(1 for x in student_avgs if x < LOW_PERCENT),
            "hardest_assignment": {"title": by_assignment[hardest[0]].title, "avg_percent": round(hardest[1], 1)}
            if hardest else None,
            "top_mistake": {**top_mistake, "error_percent": round(top_mistake["wrong"] / top_mistake["total"] * 100)}
            if top_mistake else None,
            "weekly": [
                {"week": k, "avg_percent": round(sum(v) / len(v), 1) if (v := pg["weekly"].get(k)) else None,
                 "works": len(pg["weekly"].get(k, []))}
                for k in week_keys
            ],
        })
    return {"groups": result, "distribution": distribution, "weeks": week_keys}
