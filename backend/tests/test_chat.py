from tests.conftest import make_student, make_teacher


async def _setup(client):
    t = await make_teacher(client)
    g = (await client.post("/api/v1/groups", json={"name": "7-B", "subject": "math"}, headers=t)).json()
    s = await make_student(client)
    await client.post("/api/v1/memberships", json={"code": g["join_code"], "password": g["join_password"]}, headers=s)
    await client.post(f"/api/v1/groups/{g['id']}/members/approve-all", headers=t)
    t_id = (await client.get("/api/v1/me", headers=t)).json()["id"]
    s_id = (await client.get("/api/v1/me", headers=s)).json()["id"]
    return t, s, g, t_id, s_id


async def test_teacher_and_student_exchange_messages(client):
    t, s, _, t_id, s_id = await _setup(client)

    # Ustoz o'quvchi profilidan yozadi
    r = await client.post(f"/api/v1/chats/with/{s_id}", headers=t)
    assert r.status_code == 200, r.text
    conv = r.json()
    assert conv["peer"]["id"] == s_id and conv["can_send"] and conv["unread"] == 0
    # Xabarsiz suhbat ro'yxatda ko'rinmaydi
    assert (await client.get("/api/v1/chats", headers=t)).json() == []

    r = await client.post(f"/api/v1/chats/{conv['id']}/messages", json={"text": "  Salom, uy vazifasini ko'rdingmi?  "}, headers=t)
    assert r.status_code == 201 and r.json()["from_me"] and r.json()["text"] == "Salom, uy vazifasini ko'rdingmi?"

    # O'quvchida: o'qilmagan 1 ta, o'sha suhbat (ustoz bilan)
    assert (await client.get("/api/v1/chats/unread", headers=s)).json() == {"unread": 1}
    lst = (await client.get("/api/v1/chats", headers=s)).json()
    assert len(lst) == 1 and lst[0]["id"] == conv["id"] and lst[0]["peer"]["id"] == t_id and lst[0]["unread"] == 1
    # O'quvchi ham shu suhbatni ochsa — yangi yaratilmaydi
    assert (await client.post(f"/api/v1/chats/with/{t_id}", headers=s)).json()["id"] == conv["id"]

    msgs = (await client.get(f"/api/v1/chats/{conv['id']}/messages", headers=s)).json()
    assert [m["from_me"] for m in msgs] == [False]
    assert (await client.post(f"/api/v1/chats/{conv['id']}/read", headers=s)).status_code == 204
    assert (await client.get("/api/v1/chats/unread", headers=s)).json() == {"unread": 0}

    r = await client.post(f"/api/v1/chats/{conv['id']}/messages", json={"text": "Ha, ustoz"}, headers=s)
    assert r.status_code == 201
    # Yangi xabarlarni "after" bilan olish (so'rov bilan kuzatish)
    after = msgs[-1]["created_at"]
    new = (await client.get(f"/api/v1/chats/{conv['id']}/messages", params={"after": after}, headers=t)).json()
    assert [m["text"] for m in new] == ["Ha, ustoz"]
    t_list = (await client.get("/api/v1/chats", headers=t)).json()
    assert t_list[0]["unread"] == 1 and t_list[0]["last_message_text"] == "Ha, ustoz" and not t_list[0]["last_from_me"]
    # Ustoz o'quvchi o'qiganini ko'radi
    assert t_list[0]["peer_read_at"] is not None


async def test_chat_only_within_own_groups(client):
    t, s, g, t_id, s_id = await _setup(client)
    stranger_teacher = await make_teacher(client)
    stranger_student = await make_student(client, "Bek", "Karimov")
    ss_id = (await client.get("/api/v1/me", headers=stranger_student)).json()["id"]

    assert (await client.post(f"/api/v1/chats/with/{s_id}", headers=stranger_teacher)).status_code == 403
    assert (await client.post(f"/api/v1/chats/with/{t_id}", headers=stranger_student)).status_code == 403
    assert (await client.post(f"/api/v1/chats/with/{ss_id}", headers=s)).status_code == 403  # o'quvchi ↔ o'quvchi yo'q

    conv = (await client.post(f"/api/v1/chats/with/{s_id}", headers=t)).json()
    # Begona odam suhbatni o'qiy olmaydi
    assert (await client.get(f"/api/v1/chats/{conv['id']}/messages", headers=stranger_student)).status_code == 404

    await client.post(f"/api/v1/chats/{conv['id']}/messages", json={"text": "Salom"}, headers=t)
    # O'quvchi guruhdan chiqarilsa — yozishma qoladi, lekin yangi xabar yuborilmaydi
    await client.post(f"/api/v1/groups/{g['id']}/members/{s_id}/remove", headers=t)
    r = await client.post(f"/api/v1/chats/{conv['id']}/messages", json={"text": "Yana"}, headers=t)
    assert r.status_code == 403
    got = (await client.get(f"/api/v1/chats/{conv['id']}", headers=s)).json()
    assert got["can_send"] is False
    assert len((await client.get(f"/api/v1/chats/{conv['id']}/messages", headers=s)).json()) == 1


async def test_message_validation_and_rate_limit(client):
    t, _, _, _, s_id = await _setup(client)
    conv = (await client.post(f"/api/v1/chats/with/{s_id}", headers=t)).json()
    url = f"/api/v1/chats/{conv['id']}/messages"
    assert (await client.post(url, json={"text": "   "}, headers=t)).status_code == 422
    assert (await client.post(url, json={"text": "x" * 2001}, headers=t)).status_code == 422
    for i in range(20):
        assert (await client.post(url, json={"text": f"{i}"}, headers=t)).status_code == 201
    assert (await client.post(url, json={"text": "ortiqcha"}, headers=t)).status_code == 429
