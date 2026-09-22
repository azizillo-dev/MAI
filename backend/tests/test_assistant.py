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
