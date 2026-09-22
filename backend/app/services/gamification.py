"""XP, darajalar, nishonlar (jetonlar), oylik medallar va reyting.

XP formulasi (bitta ish uchun, maksimum 60):
  +10 topshirgani uchun
  +0..40 natija foiziga qarab (100% -> 40)
  +10 muddatida topshirgani uchun
Faqat yakuniy baho (o'quvchiga chiqqan) XP beradi. Ustoz bahoni o'zgartirsa, XP qayta hisoblanadi.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import utcnow
from app.models import (
    BadgeAward,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    Submission,
    SubmissionStatus,
    User,
    XpEvent,
)
from app.services.assignments import TASHKENT
from app.services.storage import signed_url

# ---------------------------------------------------------------- Darajalar

LEVEL_NAMES = [
    "Boshlovchi", "Izlanuvchi", "Tirishqoq", "Bilimdon", "Ustamon",
    "Zukko", "Donishmand", "Olim", "Akademik", "Afsona",
]


def level_floor(level: int) -> int:
    """n-darajaga yetish uchun kerakli jami XP: 0, 100, 300, 600, 1000, 1500..."""
    return 50 * level * (level - 1)


def level_info(xp: int) -> dict:
    level = 1
    while xp >= level_floor(level + 1):
        level += 1
    current, nxt = level_floor(level), level_floor(level + 1)
    return {
        "level": level,
        "level_name": LEVEL_NAMES[min(level, len(LEVEL_NAMES)) - 1],
        "level_xp": xp - current,
        "level_span": nxt - current,
    }


def points_for(sub: Submission) -> int | None:
    if sub.status != SubmissionStatus.GRADED or sub.final_score is None:
        return None
    scale = float(sub.assignment.group.grading_scale)
    percent = max(0.0, min(100.0, sub.final_score / scale * 100)) if scale else 0.0
    return 10 + round(percent * 0.4) + (0 if sub.is_late else 10)


# ---------------------------------------------------------------- Nishonlar katalogi


@dataclass(frozen=True)
class Badge:
    code: str
    name: str
    description: str
    category: str
    icon: str  # ilovadagi ikonka kaliti
    tier: str  # bronze | silver | gold | blue | green | purple
    metric: str
    target: int
    subject: str | None = None


CATEGORIES = {
    "start": "Ilk qadamlar",
    "accuracy": "Aniqlik",
    "streak": "Tirishqoqlik",
    "subject": "Fan ustasi",
    "growth": "O'sish",
}

BADGES: list[Badge] = [
    Badge("first_step", "Birinchi qadam", "Birinchi vazifani topshir", "start", "rocket", "blue", "works", 1),
    Badge("on_time_5", "Vaqt ustasi", "5 ta vazifani muddatida topshir", "start", "clock", "green", "on_time", 5),
    Badge("works_25", "Tinimsiz", "25 ta vazifa topshir", "start", "fire", "bronze", "works", 25),
    Badge("perfect_1", "Mukammal", "Birinchi marta 100% natija ol", "accuracy", "diamond", "blue", "perfect", 1),
    Badge("high_10", "Kuchli idrok", "10 ta ishda a'lo natija (86%+)", "accuracy", "brain", "purple", "high", 10),
    Badge("perfect_5", "Mohir mergan", "5 marta 100% natija ol", "accuracy", "target", "gold", "perfect", 5),
    Badge("streak_3", "3 seriya", "Ketma-ket 3 ta ishni muddatida topshir", "streak", "bolt", "bronze", "streak", 3),
    Badge("streak_10", "10 seriya", "Ketma-ket 10 ta ishni muddatida topshir", "streak", "bolt", "silver", "streak", 10),
    Badge("streak_25", "Temir iroda", "Ketma-ket 25 ta ishni muddatida topshir", "streak", "shield", "gold", "streak", 25),
    Badge("math_master", "Hisob ustasi", "Matematikadan 10 ta a'lo ish", "subject", "calculate", "blue", "subject_high", 10, "math"),
    Badge("math_star", "Matematika yulduzi", "Matematikadan 30 ta a'lo ish", "subject", "functions", "gold", "subject_high", 30, "math"),
    Badge("english_words", "So'z ustasi", "Ingliz tilidan 10 ta a'lo ish", "subject", "translate", "green", "subject_high", 10, "english"),
    Badge("english_star", "Ingliz tili yulduzi", "Ingliz tilidan 30 ta a'lo ish", "subject", "language", "gold", "subject_high", 30, "english"),
    Badge("comeback", "Qayta tiklanish", "Past natijadan keyin a'lo natija ol", "growth", "trending", "green", "comeback", 1),
    Badge("grower", "O'sish yo'lida", "Ketma-ket 3 marta natijangni yaxshila", "growth", "stairs", "purple", "growth_run", 3),
]
BADGES_BY_CODE = {b.code: b for b in BADGES}

MEDALS = {1: ("month_gold", "Oy chempioni", "gold"), 2: ("month_silver", "Oyning 2-o'rni", "silver"),
          3: ("month_bronze", "Oyning 3-o'rni", "bronze")}


async def _graded(db: AsyncSession, student_id: uuid.UUID) -> list[Submission]:
    return list(
        await db.scalars(
            select(Submission)
            .where(Submission.student_id == student_id, Submission.status == SubmissionStatus.GRADED)
            .order_by(Submission.submitted_at)
        )
    )


def _percent(s: Submission) -> float:
    scale = float(s.assignment.group.grading_scale)
    return (s.final_score or 0) / scale * 100 if scale else 0


def compute_metrics(subs: list[Submission]) -> dict[str, int]:
    """Nishonlar va profil statistikasi uchun ko'rsatkichlar (faqat yakuniy baholangan ishlar)."""
    percents = [_percent(s) for s in subs]
    best_streak = streak = 0
    for s in subs:
        streak = 0 if s.is_late else streak + 1
        best_streak = max(best_streak, streak)
    growth = best_growth = 0
    comeback = 0
    for prev, cur in zip(percents, percents[1:], strict=False):
        growth = growth + 1 if cur > prev else 0
        best_growth = max(best_growth, growth)
        if prev < 51 and cur >= 86:
            comeback = 1
    subject_high: dict[str, int] = {}
    for s, p in zip(subs, percents, strict=True):
        if p >= 86:
            subj = s.assignment.group.subject
            subject_high[subj] = subject_high.get(subj, 0) + 1
    return {
        "works": len(subs),
        "on_time": sum(1 for s in subs if not s.is_late),
        "perfect": sum(1 for p in percents if p >= 99.5),
        "high": sum(1 for p in percents if p >= 86),
        "streak": best_streak,
        "current_streak": streak,
        "growth_run": best_growth,
        "comeback": comeback,
        **{f"subject_high:{k}": v for k, v in subject_high.items()},
        "avg_percent": round(sum(percents) / len(percents)) if percents else 0,
    }


def badge_value(b: Badge, m: dict[str, int]) -> int:
    key = f"subject_high:{b.subject}" if b.metric == "subject_high" else b.metric
    return m.get(key, 0)


async def evaluate_badges(db: AsyncSession, student_id: uuid.UUID) -> list[str]:
    """Yetib kelgan, lekin hali berilmagan nishonlarni beradi. Yangi berilganlar kodlarini qaytaradi."""
    m = compute_metrics(await _graded(db, student_id))
    have = set(
        await db.scalars(
            select(BadgeAward.badge_code).where(BadgeAward.student_id == student_id, BadgeAward.source == "system")
        )
    )
    new = []
    for b in BADGES:
        if b.code not in have and badge_value(b, m) >= b.target:
            db.add(BadgeAward(student_id=student_id, badge_code=b.code, source="system", awarded_at=utcnow()))
            new.append(b.code)
    return new


async def on_submission_final(db: AsyncSession, sub: Submission) -> None:
    """Baho yakunlanganda (AI yoki ustoz) chaqiriladi: XP yozuvi va nishonlar. Commit chaqiruvchida."""
    pts = points_for(sub)
    ev = await db.scalar(select(XpEvent).where(XpEvent.submission_id == sub.id))
    if pts is None:
        if ev is not None:
            await db.delete(ev)
        return
    if ev is None:
        db.add(XpEvent(student_id=sub.student_id, group_id=sub.assignment.group_id, submission_id=sub.id,
                       points=pts, created_at=utcnow()))
    else:
        ev.points = pts
    await db.flush()
    await evaluate_badges(db, sub.student_id)


# ---------------------------------------------------------------- Reyting


def period_start(period: str, now: datetime | None = None) -> datetime | None:
    now = now or utcnow()
    if period == "month":
        local = now.astimezone(TASHKENT)
        return local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if period == "3months":
        return now - timedelta(days=90)
    return None


async def scope_students(db: AsyncSession, group: Group, scope: str) -> list[User]:
    """scope=group: shu guruh; scope=teacher: shu ustozning barcha faol guruhlaridagi o'quvchilar."""
    q = select(User).join(GroupMember, GroupMember.student_id == User.id).where(GroupMember.status == MemberStatus.ACTIVE)
    if scope == "teacher":
        q = q.join(Group, Group.id == GroupMember.group_id).where(
            Group.teacher_id == group.teacher_id, Group.status == GroupStatus.ACTIVE
        )
    else:
        q = q.where(GroupMember.group_id == group.id)
    return list((await db.scalars(q.distinct())).all())


async def leaderboard(db: AsyncSession, group: Group, scope: str, period: str) -> list[dict]:
    students = await scope_students(db, group, scope)
    if not students:
        return []
    ids = [s.id for s in students]
    q = select(XpEvent.student_id, func.sum(XpEvent.points)).where(XpEvent.student_id.in_(ids)).group_by(XpEvent.student_id)
    if scope == "teacher":
        q = q.join(Group, Group.id == XpEvent.group_id).where(Group.teacher_id == group.teacher_id)
    else:
        q = q.where(XpEvent.group_id == group.id)
    start = period_start(period)
    if start is not None:
        q = q.where(XpEvent.created_at >= start)
    points = {sid: int(p or 0) for sid, p in (await db.execute(q)).all()}
    totals = {sid: int(p or 0) for sid, p in (await db.execute(
        select(XpEvent.student_id, func.sum(XpEvent.points)).where(XpEvent.student_id.in_(ids)).group_by(XpEvent.student_id)
    )).all()}

    rows = sorted(students, key=lambda u: (-points.get(u.id, 0), u.first_name, u.last_name))
    out, rank, prev = [], 0, None
    for i, u in enumerate(rows, start=1):
        pts = points.get(u.id, 0)
        if pts != prev:  # teng ball — teng o'rin
            rank, prev = i, pts
        out.append({
            "rank": rank,
            "student_id": u.id,
            "name": u.full_name,
            "avatar_url": signed_url(u.avatar_key) if u.avatar_key else None,
            "points": pts,
            "level": level_info(totals.get(u.id, 0))["level"],
        })
    return out


# ---------------------------------------------------------------- Oylik medallar


# (guruh, oy) juftliklari: shu jarayonda allaqachon tekshirilgan. O'tgan oy XP'si o'zgarmaydi,
# shuning uchun qayta tekshirish shart emas (bir nechta jarayonda ham xavfsiz: tekshiruv idempotent)
_medals_checked: set[tuple] = set()


async def award_monthly_medals(db: AsyncSession, group: Group) -> None:
    """O'tgan oy uchun 1-3-o'rin medallarini beradi (idempotent). Worker yo'q: reyting/profil ochilganda chaqiriladi."""
    now_local = utcnow().astimezone(TASHKENT)
    this_month = now_local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    prev_month = (this_month - timedelta(days=1)).replace(day=1)
    key = prev_month.strftime("%Y-%m")
    if (group.id, key) in _medals_checked:
        return

    existing = await db.scalar(
        select(func.count()).select_from(BadgeAward).where(
            BadgeAward.group_id == group.id, BadgeAward.source == "monthly", BadgeAward.period == key
        )
    )
    if existing:
        _medals_checked.add((group.id, key))
        return
    rows = (await db.execute(
        select(XpEvent.student_id, func.sum(XpEvent.points).label("pts"))
        .where(XpEvent.group_id == group.id, XpEvent.created_at >= prev_month, XpEvent.created_at < this_month)
        .group_by(XpEvent.student_id)
        .order_by(func.sum(XpEvent.points).desc())
        .limit(3)
    )).all()
    for rank, (sid, pts) in enumerate(rows, start=1):
        if not pts:
            continue
        code, _, _ = MEDALS[rank]
        db.add(BadgeAward(student_id=sid, badge_code=code, source="monthly", group_id=group.id, period=key,
                          meta={"rank": rank, "points": int(pts), "group": group.name},
                          awarded_at=utcnow()))
    if rows:
        await db.commit()
    _medals_checked.add((group.id, key))


# ---------------------------------------------------------------- O'quvchi progressi


async def student_progress(db: AsyncSession, student: User) -> dict:
    subs = await _graded(db, student.id)
    m = compute_metrics(subs)
    xp = int(await db.scalar(select(func.coalesce(func.sum(XpEvent.points), 0)).where(XpEvent.student_id == student.id)))
    awards = list(await db.scalars(select(BadgeAward).where(BadgeAward.student_id == student.id).order_by(BadgeAward.awarded_at)))
    earned = {a.badge_code: a for a in awards if a.source == "system"}

    badges = []
    for b in BADGES:
        a = earned.get(b.code)
        badges.append({
            "code": b.code, "name": b.name, "description": b.description, "category": b.category,
            "category_name": CATEGORIES[b.category], "icon": b.icon, "tier": b.tier, "subject": b.subject,
            "target": b.target, "value": min(badge_value(b, m), b.target),
            "earned_at": a.awarded_at if a else None,
        })
    medals = [
        {"code": a.badge_code, "name": next(n for c, n, _ in MEDALS.values() if c == a.badge_code),
         "tier": next(t for c, _, t in MEDALS.values() if c == a.badge_code), "month": a.period,
         **(a.meta or {}), "awarded_at": a.awarded_at}
        for a in awards if a.source == "monthly"
    ]
    gifts = [{"code": a.badge_code, "awarded_at": a.awarded_at, **(a.meta or {})} for a in awards if a.source == "gift"]

    # Eng yaxshi guruhdagi o'rni (shu oy)
    ranks = []
    for gm in await db.scalars(
        select(GroupMember).where(GroupMember.student_id == student.id, GroupMember.status == MemberStatus.ACTIVE)
    ):
        if gm.group.status != GroupStatus.ACTIVE:
            continue
        await award_monthly_medals(db, gm.group)
        board = await leaderboard(db, gm.group, "group", "month")
        me = next((r for r in board if r["student_id"] == student.id), None)
        if me:
            ranks.append({"group_id": gm.group.id, "group_name": gm.group.name, "rank": me["rank"], "of": len(board)})

    return {
        "xp": xp,
        **level_info(xp),
        "stats": {
            "works": m["works"], "avg_percent": m["avg_percent"], "current_streak": m["current_streak"],
            "best_streak": m["streak"], "badges_earned": len(earned), "badges_total": len(BADGES),
        },
        "ranks": sorted(ranks, key=lambda r: r["rank"]),
        "badges": badges,
        "medals": medals,
        "gifts": gifts,
    }

