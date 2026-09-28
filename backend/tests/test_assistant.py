from app.db import session as db_session
from app.models import User
from app.services import jobs
from app.services.assistant_tools import AssistantTools, _trend
from tests.conftest import make_student, make_teacher
from tests.test_assignments import _published, _setup, _submit


def test_trend():
    assert _trend([50, 55, 80, 90])["direction"] == "o'smoqda"
    assert _trend([90, 88, 60, 55])["direction"] == "pasaymoqda"
    assert _trend([80, 82, 79, 81])["direction"] == "barqaror"
    assert _trend([80])["direction"] == "ma'lumot kam"


async def _teacher_user(client, headers) -> User:
    me = (await client.get("/api/v1/me", headers=headers)).json()
    async with db_session.get_sessionmaker()() as db:
        return await db.get(User, __import__("uuid").UUID(me["id"]))


async def test_tools_give_exact_numbers_and_stay_in_scope(client):
    t, g, (s1, s2) = await _setup(client, 2)
    a = await _published(client, t, g)
    await _submit(client, s1, a)
    await jobs.drain()

    teacher = await _teacher_user(client, t)
    async with db_session.get_sessionmaker()() as db:
        tools = AssistantTools(db, teacher)
        found = await tools.find_students("ali")  # make_student: "Ali Valiyev"
        assert found["count"] == 2
        sid = found["matches"][0]["student_id"]
        report = await tools.student_report(sid)
        assert report["name"] == "Ali Valiyev" and report["group_size"] == 2
        group = await tools.group_report(str(g["id"]))
        assert group["students"] == 2 and group["avg_percent"] == 80.0  # 10 ballik: 8 -> 80%
        assert tools.attachments[0]["type"] == "student" and tools.attachments[1]["type"] == "group"

        # Begona o'quvchi va guruh ma'lumoti berilmaydi
        outsider_h = await make_student(client)
        outsider = (await client.get("/api/v1/me", headers=outsider_h)).json()["id"]
        assert "error" in await tools.student_report(outsider)
        other_t = await make_teacher(client)
        other_g = (await client.post("/api/v1/groups", json={"name": "Boshqa", "subject": "math"}, headers=other_t)).json()
        assert "error" in await tools.group_report(other_g["id"])
        assert "error" in await tools.student_report("not-a-uuid")


async def test_assistant_endpoint(client):
    t, g, (s,) = await _setup(client, 1)
    r = await client.post("/api/v1/teachers/me/assistant", headers=t,
                          json={"messages": [{"role": "user", "content": "Ali qanday o'qiyapti?"}]})
    assert r.status_code == 200, r.text
    body = r.json()
    assert "Ali Valiyev" in body["reply"] and "student_report" in body["tools"]
    assert body["attachments"][0]["name"] == "Ali Valiyev"

    r = await client.post("/api/v1/teachers/me/assistant", headers=s,
                          json={"messages": [{"role": "user", "content": "salom"}]})
    assert r.status_code == 403  # o'quvchi foydalana olmaydi


async def test_new_tools_below_threshold_topics_and_create(client, monkeypatch):
    from datetime import UTC, datetime, timedelta

    from sqlalchemy import update

    from app.ai import provider as ai
    from app.ai.schemas import GradedItem, GradeResult
    from app.models import Assignment

    t, g, (s1, s2, s3) = await _setup(client, 3)
    a = await _published(client, t, g)
    fake = ai.get_provider()
    real = fake.grade
    scores = iter([95, 40])

    async def graded(ctx, work, text):
        pct = next(scores)
        verdict = "correct" if pct > 50 else "incorrect"
        items = [GradedItem(number=str(i.get("number")), verdict=verdict, comment="" if pct > 50 else "Maxrajni unutgan")
                 for i in ctx.items]
        return GradeResult(matches_assignment=True, items=items, score_percent=pct, feedback_student="...",
                           note_teacher="...", confidence=0.95), (await real(ctx, work, text))[1]

    monkeypatch.setattr(fake, "grade", graded)
    await _submit(client, s1, a)
    await jobs.drain()
    await _submit(client, s2, a, color=(200, 40, 40))
    await jobs.drain()
    # Muddatni o'tmishga suramiz: vositalar faqat muddati o'tgan vazifalarni hisoblaydi
    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(Assignment).values(due_at=datetime.now(UTC) - timedelta(hours=1)))
        await db.commit()

    teacher = await _teacher_user(client, t)
    async with db_session.get_sessionmaker()() as db:
        tools = AssistantTools(db, teacher)
        low = await tools.students_below(str(g["id"]), 70, 3)
        assert [x["avg_percent"] for x in low["below_threshold"]] == [40.0]
        assert len(low["did_not_submit"]) == 1  # uchinchi o'quvchi topshirmagan

        topics = await tools.difficult_topics(str(g["id"]))
        worst = topics["hardest_items"][0]
        assert worst["error_rate_percent"] == 50 and worst["comments"] == ["Maxrajni unutgan"]

        made = await tools.create_assignment(str(g["id"]), "Kasrlarni qo'shish", 12, "hard", 2)
        assert made["created"] and tools.attachments[-1]["type"] == "assignment"
    await jobs.drain()
    created = (await client.get(f"/api/v1/assignments/{made['assignment_id']}", headers=t)).json()
    # Qoralama: ustoz e'lon qilmaguncha o'quvchi ko'rmaydi
    assert created["status"] == "review" and len(created["items"]) == 12
    tasks = (await client.get("/api/v1/student/assignments", headers=s1)).json()
    assert made["assignment_id"] not in [x["id"] for x in tasks]
