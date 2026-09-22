from datetime import UTC, datetime, timedelta

from sqlalchemy import update

from app.db import session as db_session
from app.models import XpEvent
from app.services import jobs
from app.services.gamification import level_info
from tests.conftest import make_student, make_teacher
from tests.test_assignments import _published, _setup, _submit, png_bytes


def test_levels():
    assert level_info(0)["level"] == 1
    assert level_info(99)["level"] == 1 and level_info(100)["level"] == 2
    info = level_info(350)
    assert info["level"] == 3 and info["level_xp"] == 50 and info["level_span"] == 300


async def test_xp_badges_and_leaderboard(client):
    t, g, (s1, s2) = await _setup(client, 2)
    a = await _published(client, t, g)
    await _submit(client, s1, a)
    await jobs.drain()

    p = (await client.get("/api/v1/students/me/progress", headers=s1)).json()
    # 10 ballik guruh, fake AI 85% -> 8 ball -> 80%: 10 + 32 + 10 (muddatida) = 52 XP
    assert p["xp"] == 52 and p["level"] == 1
    earned = {b["code"] for b in p["badges"] if b["earned_at"]}
    assert earned == {"first_step"}
    streak3 = next(b for b in p["badges"] if b["code"] == "streak_3")
    assert streak3["value"] == 1 and streak3["target"] == 3 and streak3["earned_at"] is None
    assert p["ranks"][0]["rank"] == 1 and p["ranks"][0]["of"] == 2

    board = (await client.get(f"/api/v1/leaderboard?group_id={g['id']}", headers=s2)).json()
    assert [e["points"] for e in board["entries"]] == [52, 0]
    assert board["me"]["rank"] == 2 and board["me"]["points"] == 0
    # Ustoz ham o'z guruhi reytingini ko'radi
    assert (await client.get(f"/api/v1/leaderboard?group_id={g['id']}&period=all", headers=t)).status_code == 200


async def test_teacher_override_recomputes_xp(client):
    t, g, (s,) = await _setup(client, 1)
    a = await _published(client, t, g)
    await _submit(client, s, a)
    await jobs.drain()
    sub_id = (await client.get(f"/api/v1/assignments/{a['id']}/submissions", headers=t)).json()[0]["id"]
    await client.post(f"/api/v1/submissions/{sub_id}/review", headers=t, json={"score": 10, "comment": "A'lo"})
    p = (await client.get("/api/v1/students/me/progress", headers=s)).json()
    assert p["xp"] == 60  # 10 + 40 + 10
    assert any(b["code"] == "perfect_1" and b["earned_at"] for b in p["badges"])


async def test_leaderboard_privacy_and_scope(client):
    t, g, (s,) = await _setup(client, 1)
    outsider = await make_student(client)
    assert (await client.get(f"/api/v1/leaderboard?group_id={g['id']}", headers=outsider)).status_code == 404
    other_teacher = await make_teacher(client)
    assert (await client.get(f"/api/v1/leaderboard?group_id={g['id']}", headers=other_teacher)).status_code == 404
    r = (await client.get(f"/api/v1/leaderboard?group_id={g['id']}&scope=teacher", headers=s)).json()
    assert r["scope"] == "teacher" and len(r["entries"]) == 1


async def test_monthly_medals_awarded_once(client):
    t, g, (s1, s2) = await _setup(client, 2)
    a = await _published(client, t, g)
    await _submit(client, s1, a)
    await jobs.drain()
    # XP'ni o'tgan oyga suramiz
    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(XpEvent).values(created_at=datetime.now(UTC) - timedelta(days=40)))
        await db.commit()
    for _ in range(2):  # ikki marta ochilsa ham medal bir marta beriladi
        await client.get(f"/api/v1/leaderboard?group_id={g['id']}", headers=s1)
    p = (await client.get("/api/v1/students/me/progress", headers=s1)).json()
    assert len(p["medals"]) == 1 and p["medals"][0]["code"] == "month_gold" and p["medals"][0]["rank"] == 1
    assert (await client.get("/api/v1/students/me/progress", headers=s2)).json()["medals"] == []


async def test_avatar_upload_and_teacher_name_edit(client):
    t, g, (s,) = await _setup(client, 1)
    r = await client.post("/api/v1/me/avatar", headers=s, files={"file": ("a.png", png_bytes(), "image/png")})
    assert r.status_code == 200 and r.json()["avatar_url"]
    members = (await client.get(f"/api/v1/groups/{g['id']}/members", headers=t)).json()
    assert members[0]["avatar_url"]
    assert (await client.delete("/api/v1/me/avatar", headers=s)).json()["avatar_url"] is None

    r = await client.patch("/api/v1/me", headers=t, json={"first_name": "Aziz"})
    assert r.json()["first_name"] == "Aziz"
    ctx = (await client.get("/api/v1/teachers/me/onboarding", headers=t)).json()["ai_context"]
    assert "Aziz Nabiyev" in ctx
    r = await client.patch("/api/v1/me", headers=s, json={"first_name": "Boshqa"})
    assert r.status_code == 403
