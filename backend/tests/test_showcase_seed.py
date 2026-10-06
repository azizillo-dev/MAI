import uuid

from sqlalchemy import update

from app.db import session as db_session
from app.models import User
from tests.conftest import make_student, make_teacher

EMAIL = "ustoz.taqdimot@gmail.com"


async def _set_email(client, headers):
    me = (await client.get("/api/v1/me", headers=headers)).json()
    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(User).where(User.id == uuid.UUID(me["id"])).values(email=EMAIL))
        await db.commit()


async def test_showcase_seed_adds_university_group_without_touching_real_data(client):
    from tools.showcase_seed import GROUP_NAME, seed

    t = await make_teacher(client)
    await _set_email(client, t)
    real_group = (await client.post("/api/v1/groups", json={"name": "11-A", "subject": "math"}, headers=t)).json()
    await make_student(client)  # haqiqiy foydalanuvchi
    before = (await client.get("/api/v1/site/public")).json()["stats"]

    await seed(EMAIL, None, False)
    await seed(EMAIL, None, False)  # qayta ishga tushirish — dublikat yaratmaydi

    groups = (await client.get("/api/v1/groups", headers=t)).json()
    names = sorted(g["name"] for g in groups)
    assert names == sorted(["11-A", GROUP_NAME])
    demo = next(g for g in groups if g["name"] == GROUP_NAME)
    members = (await client.get(f"/api/v1/groups/{demo['id']}/members", headers=t)).json()
    assert len([m for m in members if m["status"] == "active"]) == 24

    d = (await client.get("/api/v1/teachers/me/dashboard", headers=t)).json()
    ga = next(x for x in d["analytics"]["groups"] if x["name"] == GROUP_NAME)
    assert ga["students"] == 24 and ga["checked"] > 200 and ga["avg_percent"] is not None
    assert any(w is not None for w in ga["weekly"])
    assert d["stats"]["to_review"] >= 2 and d["stats"]["drafts"] >= 1

    r = await client.get(f"/api/v1/groups/{demo['id']}/report.pdf?period=all", headers=t)
    assert r.status_code == 200 and r.content[:4] == b"%PDF"

    # Universitet profili: AI kontekstida ko'rinadi, oldingi javoblar saqlangan
    ob = (await client.get("/api/v1/teachers/me/onboarding", headers=t)).json()
    assert ob["answers"]["teaching_place"] == "university" and "university" in ob["answers"]["student_levels"]
    assert "Universitet" in ob["ai_context"]

    # Saytdagi ochiq statistika demo talabalar bilan oshmaydi
    assert (await client.get("/api/v1/site/public")).json()["stats"] == before

    # O'chirish: faqat demo qism ketadi
    await seed(EMAIL, None, True)
    groups = (await client.get("/api/v1/groups", headers=t)).json()
    assert [g["id"] for g in groups] == [real_group["id"]]
