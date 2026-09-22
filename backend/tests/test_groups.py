from tests.conftest import make_student, make_teacher


async def _approve_all(client, t, g):
    r = await client.post(f"/api/v1/groups/{g['id']}/members/approve-all", headers=t)
    assert r.status_code == 200, r.text
    return r.json()


async def _group(client, h, **kw):
    r = await client.post("/api/v1/groups", json={"name": "7-B matematika", "subject": "math", **kw}, headers=h)
    assert r.status_code == 201, r.text
    return r.json()


async def test_create_group_uses_teacher_default_scale(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    assert g["grading_scale"] == "10"
    assert len(g["join_code"]) == 9 and g["join_code"][4] == "-"
    assert len(g["join_password"]) == 8 and g["join_password"].isdigit() and g["join_password"][0] != "0"
    assert g["join_enabled"] is True
    assert g["invite_url"].endswith(g["invite_url"].split("?t=")[1])


async def test_free_plan_group_limit(client):
    t = await make_teacher(client)
    await _group(client, t)
    r = await client.post("/api/v1/groups", json={"name": "Ikkinchi", "subject": "math"}, headers=t)
    assert r.status_code == 403 and r.json()["error"]["code"] == "PLAN_GROUP_LIMIT"
    plan = (await client.get("/api/v1/teachers/me/plan", headers=t)).json()
    assert plan["plan"]["code"] == "trial" and plan["status"] == "trial" and plan["days_left"] == 14
    assert plan["groups_used"] == 1


async def test_student_joins_with_code_and_password(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)

    # Kichik harf va chiziqchasiz kod ham qabul qilinadi
    code = g["join_code"].replace("-", "").lower()
    p = await client.post("/api/v1/memberships/preview", json={"code": code}, headers=s)
    assert p.status_code == 200
    assert p.json()["teacher_name"] == "Azizillo Nabiyev" and p.json()["group_name"] == "7-B matematika"

    # Parol bo'sh joy bilan kiritilsa ham ("4829 1375") qabul qilinadi
    pretty = g["join_password"][:4] + " " + g["join_password"][4:]
    r = await client.post("/api/v1/memberships", json={"code": code, "password": pretty}, headers=s)
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "pending"  # ustoz tasdiqlamaguncha guruhga kirmaydi

    mine = (await client.get("/api/v1/memberships", headers=s)).json()
    assert len(mine) == 1 and mine[0]["teacher"]["full_name"] == "Azizillo Nabiyev"

    r = await client.post("/api/v1/memberships", json={"code": code, "password": g["join_password"]}, headers=s)
    assert r.status_code == 409 and r.json()["error"]["code"] == "ALREADY_PENDING"

    await _approve_all(client, t, g)
    r = await client.post("/api/v1/memberships", json={"code": code, "password": g["join_password"]}, headers=s)
    assert r.status_code == 409 and r.json()["error"]["code"] == "ALREADY_MEMBER"


async def test_join_via_invite_token_and_rotation_invalidates(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    token = g["invite_url"].split("?t=")[1]

    s1 = await make_student(client)
    r = await client.post("/api/v1/memberships", json={"code": g["join_code"], "invite_token": token}, headers=s1)
    assert r.status_code == 201

    await _approve_all(client, t, g)
    g2 = (await client.post(f"/api/v1/groups/{g['id']}/rotate-credentials", headers=t)).json()
    assert g2["join_password"] != g["join_password"] and g2["invite_url"] != g["invite_url"]
    assert g2["join_code"] == g["join_code"]  # kod o'zgarmaydi
    assert g2["members_active"] == 1  # a'zolar guruhda qoladi

    s2 = await make_student(client)
    r = await client.post("/api/v1/memberships", json={"code": g["join_code"], "invite_token": token}, headers=s2)
    assert r.status_code == 400 and r.json()["error"]["code"] == "INVITE_EXPIRED"


async def test_wrong_password_lockout(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)
    wrong = "000000" if g["join_password"] != "000000" else "111111"
    for _ in range(5):
        r = await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": wrong}, headers=s)
        assert r.json()["error"]["code"] == "GROUP_PASSWORD_INVALID"
    r = await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s)
    assert r.status_code == 429 and r.json()["error"]["code"] == "JOIN_LOCKED"


async def test_unknown_code(client):
    s = await make_student(client)
    r = await client.post("/api/v1/memberships/preview", json={"code": "ZZZ-ZZZ"}, headers=s)
    assert r.status_code == 404 and r.json()["error"]["code"] == "GROUP_CODE_INVALID"


async def test_approval_flow(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)
    r = await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s)
    assert r.json()["status"] == "pending"

    members = (await client.get(f"/api/v1/groups/{g['id']}/members", headers=t)).json()
    assert members[0]["status"] == "pending"
    sid = members[0]["student_id"]

    r = await client.post(f"/api/v1/groups/{g['id']}/members/{sid}/approve", headers=t)
    assert r.status_code == 200 and r.json()["status"] == "active"
    assert (await client.get("/api/v1/memberships", headers=s)).json()[0]["status"] == "active"


async def test_student_limit_counts_unique_students(client):
    from app.core.config import get_settings  # noqa: F401
    from app.db import session as db_session
    from app.models import Plan
    from sqlalchemy import update

    async with db_session.get_sessionmaker()() as db:
        await db.execute(update(Plan).where(Plan.code == "trial").values(max_students=2))
        await db.commit()

    t = await make_teacher(client)
    g = await _group(client, t)
    body = {"code": g["join_code"], "password": g["join_password"]}
    for _ in range(3):
        assert (await client.post("/api/v1/memberships", json=body, headers=await make_student(client))).status_code == 201
    # 3 ta so'rov bor, limit 2: faqat 2 tasi qabul qilinadi
    r = await client.post(f"/api/v1/groups/{g['id']}/members/approve-all", headers=t)
    assert r.json() == {"approved": 2, "left_pending": 1, "limit": 2}
    r = await client.post("/api/v1/memberships", json=body, headers=await make_student(client))
    assert r.status_code == 403 and r.json()["error"]["code"] == "GROUP_FULL"


async def test_student_in_multiple_groups_of_different_teachers(client):
    s = await make_student(client)
    for _ in range(2):
        t = await make_teacher(client)
        g = await _group(client, t)
        r = await client.post(
            "/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s
        )
        assert r.status_code == 201
    assert len((await client.get("/api/v1/memberships", headers=s)).json()) == 2


async def test_teacher_cannot_see_foreign_group(client):
    t1 = await make_teacher(client)
    t2 = await make_teacher(client)
    g = await _group(client, t1)
    r = await client.get(f"/api/v1/groups/{g['id']}", headers=t2)
    assert r.status_code == 404


async def test_profile_locked_until_teacher_grants_once(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)
    await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s)
    await _approve_all(client, t, g)

    r = await client.patch("/api/v1/students/me/profile", json={"first_name": "Vali"}, headers=s)
    assert r.status_code == 403 and r.json()["error"]["code"] == "PROFILE_LOCKED"

    sid = (await client.get("/api/v1/me", headers=s)).json()["id"]
    r = await client.post(f"/api/v1/groups/{g['id']}/members/{sid}/grant-profile-edit", headers=t)
    assert r.status_code == 200, r.text
    assert (await client.get("/api/v1/me", headers=s)).json()["student"]["can_edit"] is True

    r = await client.patch("/api/v1/students/me/profile", json={"first_name": "Vali"}, headers=s)
    assert r.status_code == 200 and r.json()["first_name"] == "Vali"
    assert r.json()["student"]["can_edit"] is False

    # Ruxsat bir martalik
    r = await client.patch("/api/v1/students/me/profile", json={"first_name": "Soli"}, headers=s)
    assert r.status_code == 403


async def test_leave_and_rejoin(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)
    body = {"code": g["join_code"], "password": g["join_password"]}
    await client.post("/api/v1/memberships", json=body, headers=s)
    assert (await client.delete(f"/api/v1/memberships/{g['id']}", headers=s)).status_code == 200
    assert (await client.get("/api/v1/memberships", headers=s)).json() == []
    assert (await client.post("/api/v1/memberships", json=body, headers=s)).status_code == 201


async def test_join_closed_and_reopened(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    body = {"code": g["join_code"], "password": g["join_password"]}
    token = g["invite_url"].split("?t=")[1]

    r = await client.post(f"/api/v1/groups/{g['id']}/join-status", json={"enabled": False}, headers=t)
    assert r.status_code == 200 and r.json()["join_enabled"] is False

    s = await make_student(client)
    for path, payload in [
        ("/api/v1/memberships/preview", {"code": g["join_code"]}),
        ("/api/v1/memberships", body),
        ("/api/v1/memberships", {"code": g["join_code"], "invite_token": token}),  # QR ham yopiq
    ]:
        r = await client.post(path, json=payload, headers=s)
        assert r.status_code == 403 and r.json()["error"]["code"] == "JOIN_CLOSED", path

    r = await client.post(f"/api/v1/groups/{g['id']}/join-status", json={"enabled": True}, headers=t)
    assert r.json()["join_enabled"] is True
    assert (await client.post("/api/v1/memberships", json=body, headers=s)).status_code == 201


async def test_codes_and_passwords_unique_across_groups(client):
    codes, passwords = set(), set()
    for _ in range(4):
        t = await make_teacher(client)
        g = await _group(client, t)
        codes.add(g["join_code"])
        passwords.add(g["join_password"])
    assert len(codes) == 4 and len(passwords) == 4


async def test_busy_password_is_never_reused(client):
    """Generator tasodifan band parolni qaytarsa ham, boshqa parol tanlanadi."""
    from app.services import groups as svc

    t1 = await make_teacher(client)
    g1 = await _group(client, t1)
    values = iter([g1["join_password"], "77777777"])
    original = svc._new_password
    svc._new_password = lambda: next(values)
    try:
        t2 = await make_teacher(client)
        g2 = await _group(client, t2)
    finally:
        svc._new_password = original
    assert g2["join_password"] == "77777777"


async def test_rejected_student_can_request_again(client):
    t = await make_teacher(client)
    g = await _group(client, t)
    s = await make_student(client)
    body = {"code": g["join_code"], "password": g["join_password"]}
    await client.post("/api/v1/memberships", json=body, headers=s)
    sid = (await client.get("/api/v1/me", headers=s)).json()["id"]
    await client.post(f"/api/v1/groups/{g['id']}/members/{sid}/reject", headers=t)
    assert (await client.get("/api/v1/memberships", headers=s)).json() == []
    r = await client.post("/api/v1/memberships", json=body, headers=s)
    assert r.status_code == 201 and r.json()["status"] == "pending"
