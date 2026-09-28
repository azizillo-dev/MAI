from tests.conftest import make_student, make_teacher
from tests.test_assignments import _setup
from tests.test_billing_email import _admin


async def test_support_message_and_admin_reply(client):
    s = await make_student(client)
    r = await client.post("/api/v1/support", headers=s, json={"kind": "suggestion", "text": "Tungi rejim qo'shing"})
    assert r.status_code == 201 and r.json()["status"] == "open"

    a = await _admin(client)
    inbox = (await client.get("/api/v1/admin/support", headers=a)).json()
    assert len(inbox) == 1 and inbox[0]["user"]["role"] == "student"
    await client.post(f"/api/v1/admin/support/{inbox[0]['id']}/reply", headers=a, json={"reply": "Rahmat, qo'shamiz!"})

    mine = (await client.get("/api/v1/support", headers=s)).json()
    assert mine[0]["status"] == "answered" and mine[0]["admin_reply"] == "Rahmat, qo'shamiz!"
    # Boshqa foydalanuvchi birovning murojaatini ko'rmaydi
    other = await make_student(client)
    assert (await client.get("/api/v1/support", headers=other)).json() == []


async def test_jeton_purchase_approve_and_gift(client):
    t, g, (s,) = await _setup(client, 1)
    info = (await client.get("/api/v1/teachers/jetons", headers=t)).json()
    star = next(j for j in info["catalog"] if j["code"] == "sinf_yulduzi")
    assert info["balances"] == {}

    # Jeton yo'q — sovg'a qilib bo'lmaydi
    me_s = (await client.get("/api/v1/me", headers=s)).json()
    gift = {"student_id": me_s["id"], "jeton_code": "sinf_yulduzi", "note": "Barakalla!"}
    r = await client.post("/api/v1/teachers/me/jetons/gift", headers=t, json=gift)
    assert r.status_code == 409 and r.json()["error"]["code"] == "JETON_BALANCE_EMPTY"

    r = await client.post("/api/v1/teachers/me/jeton-orders", headers=t, json={"jeton_code": "sinf_yulduzi", "quantity": 2})
    assert r.status_code == 201 and r.json()["amount_uzs"] == 2 * star["price_uzs"]

    a = await _admin(client)
    orders = (await client.get("/api/v1/admin/jeton-orders", headers=a)).json()
    await client.post(f"/api/v1/admin/jeton-orders/{orders[0]['id']}/approve", headers=a, json={"note": "Click"})
    assert (await client.get("/api/v1/teachers/jetons", headers=t)).json()["balances"] == {"sinf_yulduzi": 2}

    r = await client.post("/api/v1/teachers/me/jetons/gift", headers=t, json=gift)
    assert r.status_code == 201 and r.json()["balances"] == {"sinf_yulduzi": 1}

    progress = (await client.get("/api/v1/students/me/progress", headers=s)).json()
    assert progress["gifts"][0]["name"] == "Sinf yulduzi" and progress["gifts"][0]["note"] == "Barakalla!"

    # Boshqa ustozning o'quvchisiga sovg'a qilib bo'lmaydi
    stranger = await make_student(client)
    sid = (await client.get("/api/v1/me", headers=stranger)).json()["id"]
    r = await client.post("/api/v1/teachers/me/jetons/gift", headers=t, json={**gift, "student_id": sid})
    assert r.status_code == 404


async def test_admin_edits_jeton_price(client):
    a = await _admin(client)
    await make_teacher(client)  # katalog ishga tushishda yaratiladi
    r = await client.patch("/api/v1/admin/jetons/oltin_qalam", headers=a, json={"price_uzs": 9000})
    assert r.json()["price_uzs"] == 9000


async def test_site_public_and_secret(client):
    pub = (await client.get("/api/v1/site/public")).json()
    assert [p["code"] for p in pub["plans"]] == ["standard", "pro"] and pub["secret_enabled"] is False
    assert pub["downloads"]["arm64_url"].endswith(".apk")

    r = await client.post("/api/v1/site/secret", json={"password": "hech-narsa"})
    assert r.status_code == 401

    a = await _admin(client)
    assert (await client.put("/api/v1/admin/site/secret-password", headers=a, json={"password": "taqdimot-2026"})).status_code == 200
    await client.put("/api/v1/admin/site/economics", headers=a, json={"usd_uzs": 13000, "notes": "Sinov"})

    assert (await client.post("/api/v1/site/secret", json={"password": "noto'g'ri"})).status_code == 401
    secret = (await client.post("/api/v1/site/secret", json={"password": "taqdimot-2026"})).json()
    assert secret["economics"]["usd_uzs"] == 13000 and secret["economics"]["notes"] == "Sinov"
    assert secret["economics"]["grade_out_tokens"] == 3190  # tahrirlanmaganlari standart qiymatda
    # Oddiy foydalanuvchi sayt sozlamalarini o'zgartira olmaydi
    t = await make_teacher(client)
    assert (await client.put("/api/v1/admin/site/economics", headers=t, json={"usd_uzs": 1})).status_code == 403
