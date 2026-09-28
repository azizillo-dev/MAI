"""Yuklama testi uchun realistik ma'lumot: ~3000 foydalanuvchi.

FAQAT test bazasida ishlating (DATABASE_URL test bazasiga qaratilgan bo'lishi shart):
    DATABASE_URL=postgresql+asyncpg://.../mentor_test python -m tools.loadtest.seed

Tuzilma: 100 o'qituvchi (Pro tarif), har birida 2 guruh, har guruhda ~15 o'quvchi (jami 2900),
har guruhda 20 ta o'tgan va 2 ta ochiq vazifa, o'quvchilar o'tgan vazifalarning ~80% ini topshirgan.
"""

import asyncio
import random
import secrets
import sys
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import insert, text

from app.core.config import get_settings
from app.db.session import get_engine, get_sessionmaker
from app.models import (
    Assignment,
    Base,
    Group,
    GroupMember,
    Subscription,
    StudentProfile,
    Submission,
    TeacherProfile,
    User,
    XpEvent,
)
from app.services.plans import get_plan, seed_plans

TEACHERS = 100
GROUPS_PER_TEACHER = 2
STUDENTS = 2900
PAST_ASSIGNMENTS = 20
OPEN_ASSIGNMENTS = 2
SUBMIT_RATE = 0.8
BATCH = 5000

FIRST = ["Aziz", "Jasur", "Dilnoza", "Madina", "Sardor", "Nodira", "Bekzod", "Malika", "Otabek", "Zarina"]
LAST = ["Aliyev", "Karimov", "Rahimova", "Toshmatov", "Yusupova", "Qodirov", "Ergasheva", "Nazarov"]
ITEMS = [{"number": str(n), "text": f"{n}-misol", "answer": str(n * 2)} for n in range(1, 6)]
AI_ITEMS = [{"number": str(n), "verdict": "correct" if n % 4 else "partial", "comment": ""} for n in range(1, 6)]


def _code() -> str:
    return secrets.token_hex(4).upper()[:8]


async def _bulk(conn, model, rows: list[dict]) -> None:
    for i in range(0, len(rows), BATCH):
        await conn.execute(insert(model), rows[i : i + BATCH])


async def main() -> None:
    # .env yoki muhit o'zgaruvchisidan olingan haqiqiy sozlama tekshiriladi
    url = get_settings().database_url
    if "test" not in url.rsplit("/", 1)[-1]:
        sys.exit("Xavfsizlik: DATABASE_URL test bazasiga qaratilmagan (nomida 'test' bo'lishi kerak)")
    random.seed(42)
    now = datetime.now(UTC)
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    async with get_sessionmaker()() as db:
        await seed_plans(db)
        await db.commit()
        pro = await get_plan(db, "pro")

    users, teachers_p, students_p, subs = [], [], [], []
    teacher_ids = [uuid.uuid4() for _ in range(TEACHERS)]
    for i, tid in enumerate(teacher_ids):
        users.append({"id": tid, "email": f"ustoz{i}@test.uz", "role": "teacher", "first_name": random.choice(FIRST),
                      "last_name": random.choice(LAST), "locale": "uz", "is_active": True})
        teachers_p.append({"user_id": tid, "onboarding_answers": {"subject": "math", "grading_scale": "10"},
                           "onboarding_completed_at": now, "ai_context": "O'qituvchi: test.", "default_grading_scale": "10"})
        subs.append({"id": uuid.uuid4(), "teacher_id": tid, "plan_id": pro.id, "status": "active",
                     "current_period_end": now + timedelta(days=30)})
    student_ids = [uuid.uuid4() for _ in range(STUDENTS)]
    for i, sid in enumerate(student_ids):
        users.append({"id": sid, "email": f"oquvchi{i}@test.uz", "role": "student", "first_name": random.choice(FIRST),
                      "last_name": random.choice(LAST), "locale": "uz", "is_active": True})
        students_p.append({"user_id": sid, "birth_date": date(2010, 1, 1) + timedelta(days=random.randint(0, 1500)),
                           "is_locked": True})

    groups, members, assignments, submissions, xp = [], [], [], [], []
    per_group = STUDENTS // (TEACHERS * GROUPS_PER_TEACHER)
    s_iter = iter(student_ids)
    for tid in teacher_ids:
        for g in range(GROUPS_PER_TEACHER):
            gid = uuid.uuid4()
            groups.append({"id": gid, "teacher_id": tid, "name": f"{7 + g}-sinf", "subject": "math", "grading_scale": "10",
                           "join_code": _code(), "join_password": _code(), "invite_token": secrets.token_hex(16),
                           "join_enabled": True, "status": "active"})
            g_students = [next(s_iter) for _ in range(per_group)]
            for sid in g_students:
                members.append({"id": uuid.uuid4(), "group_id": gid, "student_id": sid, "status": "active",
                                "decided_at": now - timedelta(days=90)})
            for a in range(PAST_ASSIGNMENTS + OPEN_ASSIGNMENTS):
                aid = uuid.uuid4()
                past = a < PAST_ASSIGNMENTS
                due = now - timedelta(days=(PAST_ASSIGNMENTS - a) * 3) if past else now + timedelta(days=a)
                assignments.append({"id": aid, "group_id": gid, "teacher_id": tid, "title": f"{a + 1}-vazifa",
                                    "source_type": "text", "items": ITEMS, "rubric": [], "status": "published",
                                    "due_at": due, "allow_late": True, "late_penalty_percent": 0,
                                    "published_at": due - timedelta(days=3)})
                if not past:
                    continue
                for sid in g_students:
                    if random.random() > SUBMIT_RATE:
                        continue
                    sub_id = uuid.uuid4()
                    score = float(random.randint(4, 10))
                    late = random.random() < 0.1
                    at = due - timedelta(hours=random.randint(1, 60))
                    submissions.append({"id": sub_id, "assignment_id": aid, "student_id": sid, "submitted_at": at,
                                        "is_late": late, "attempt": 1, "status": "graded", "ai_items": AI_ITEMS,
                                        "ai_score_percent": score * 10, "ai_confidence": 0.9,
                                        "ai_matches_assignment": True, "feedback_student": "Yaxshi ish!",
                                        "note_teacher": "Hisobda ehtiyot bo'lsin.", "graded_at": at,
                                        "final_score": score})
                    xp.append({"id": uuid.uuid4(), "student_id": sid, "group_id": gid, "submission_id": sub_id,
                               "points": 10 + round(score * 4) + (0 if late else 10), "created_at": at})

    async with engine.begin() as conn:
        for model, rows in [(User, users), (TeacherProfile, teachers_p), (StudentProfile, students_p),
                            (Subscription, subs), (Group, groups), (GroupMember, members),
                            (Assignment, assignments), (Submission, submissions), (XpEvent, xp)]:
            await _bulk(conn, model, rows)
    async with engine.begin() as conn:
        await conn.execute(text("ANALYZE"))
    print(f"Tayyor: {len(users)} foydalanuvchi, {len(groups)} guruh, {len(assignments)} vazifa, "
          f"{len(submissions)} topshiriq, {len(xp)} XP yozuvi")


if __name__ == "__main__":
    asyncio.run(main())
