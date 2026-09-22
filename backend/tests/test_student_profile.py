from app.services import jobs
from tests.conftest import make_student, make_teacher
from tests.test_assignments import _published, _setup, _submit


async def test_teacher_sees_full_profile_classmate_sees_public(client):
    t, g, (s1, s2) = await _setup(client, 2)
    a = await _published(client, t, g)
    await _submit(client, s1, a)
    await jobs.drain()

    me1 = (await client.get("/api/v1/me", headers=s1)).json()
    sid = me1["id"]

    r = await client.get(f"/api/v1/students/{sid}/profile", headers=t)
    assert r.status_code == 200, r.text
    p = r.json()
    assert p["xp"] > 0 and p["level"] >= 1 and p["stats"]["works"] == 1
    tv = p["teacher_view"]
    assert tv["summary"]["submitted"] == 1 and tv["summary"]["avg_percent"] == 80.0
    assert tv["submissions"][0]["title"] and tv["submissions"][0]["final_score"] == 8.0
    assert tv["phone"] and p["groups"][0]["name"] == "7-B"

    # Guruhdosh: ommaviy qism, ishlar va aloqa yo'q
    r = await client.get(f"/api/v1/students/{sid}/profile", headers=s2)
    assert r.status_code == 200 and r.json()["teacher_view"] is None and r.json()["xp"] == p["xp"]

    # Begona ustoz va begona o'quvchi ko'ra olmaydi
    other_t = await make_teacher(client)
    other_s = await make_student(client)
    assert (await client.get(f"/api/v1/students/{sid}/profile", headers=other_t)).status_code == 404
    assert (await client.get(f"/api/v1/students/{sid}/profile", headers=other_s)).status_code == 404
