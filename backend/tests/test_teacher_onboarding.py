from tests.conftest import ONBOARDING, make_teacher


async def test_questions_localized(client):
    uz = (await client.get("/api/v1/teachers/onboarding/questions")).json()["questions"]
    ru = (await client.get("/api/v1/teachers/onboarding/questions?lang=ru")).json()["questions"]
    assert uz[0]["title"] == "Qaysi fandan dars berasiz?"
    assert ru[0]["title"].startswith("Какой")
    assert uz[0]["options"][0] == {"id": "math", "label": "Matematika"}


async def test_new_teacher_must_onboard_first(client):
    h = await make_teacher(client, onboard=False)
    me = (await client.get("/api/v1/me", headers=h)).json()
    assert me["next_step"] == "teacher_onboarding"
    r = await client.post("/api/v1/groups", json={"name": "7-B", "subject": "math"}, headers=h)
    assert r.status_code == 403 and r.json()["error"]["code"] == "ONBOARDING_REQUIRED"


async def test_onboarding_builds_ai_context(client):
    h = await make_teacher(client, onboard=False)
    r = await client.put("/api/v1/teachers/me/onboarding", json={"answers": ONBOARDING}, headers=h)
    assert r.status_code == 200, r.text
    ctx = r.json()["ai_context"]
    assert "Azizillo Nabiyev" in ctx
    assert "Matematika" in ctx and "10 ballik" in ctx and "Muvozanatli" in ctx
    assert "<<<Yechim yo'li yozilmasa ball kamaytirilsin>>>" in ctx

    me = (await client.get("/api/v1/me", headers=h)).json()
    assert me["next_step"] == "home"
    assert me["teacher"]["default_grading_scale"] == "10"


async def test_onboarding_validation(client):
    h = await make_teacher(client, onboard=False)
    bad = {**ONBOARDING, "subjects": ["chemistry"], "grading_scale": None, "hack": 1}
    r = await client.put("/api/v1/teachers/me/onboarding", json={"answers": bad}, headers=h)
    assert r.status_code == 422
    fields = r.json()["error"]["details"]["fields"]
    assert set(fields) == {"subjects", "grading_scale", "hack"}


async def test_student_cannot_access_teacher_routes(client):
    from tests.conftest import make_student

    h = await make_student(client)
    r = await client.put("/api/v1/teachers/me/onboarding", json={"answers": ONBOARDING}, headers=h)
    assert r.status_code == 403 and r.json()["error"]["code"] == "ROLE_FORBIDDEN"
