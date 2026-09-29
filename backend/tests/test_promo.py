from datetime import date, timedelta

from tests.conftest import make_teacher
from tests.test_billing_email import _admin


async def _create(client, a, **kw):
    body = {"code": "ustoz20", "kind": "percent", "value": 20, **kw}
    return await client.post("/api/v1/admin/promo-codes", headers=a, json=body)


async def _request(client, t, code, plan="standard", months=1):
    return await client.post("/api/v1/teachers/me/plan-requests", headers=t,
                             json={"plan_code": plan, "months": months, "promo_code": code})


async def test_percent_promo_applied_and_counted(client):
    a = await _admin(client)
    r = await _create(client, a)
    assert r.status_code == 201 and r.json()["code"] == "USTOZ20"
    assert (await _create(client, a)).status_code == 409  # bir xil kod ikkinchi marta yaratilmaydi

    t = await make_teacher(client)
    q = await client.post("/api/v1/teachers/me/promo-check", headers=t,
                          json={"plan_code": "pro", "months": 3, "code": " ustoz20 "})
    assert q.status_code == 200, q.text
    assert q.json() == {"code": "USTOZ20", "kind": "percent", "value": 20,
                        "full_uzs": 3 * 399000, "discount_uzs": 239400, "amount_uzs": 3 * 399000 - 239400}

    r = await _request(client, t, "ustoz20", plan="pro", months=3)
    assert r.status_code == 201, r.text
    assert r.json()["amount_uzs"] == 957600 and r.json()["discount_uzs"] == 239400
    assert r.json()["promo_code"] == "USTOZ20"

    pending = (await client.get("/api/v1/admin/requests", headers=a)).json()
    assert pending[0]["promo_code"] == "USTOZ20" and pending[0]["discount_uzs"] == 239400
    await client.post(f"/api/v1/admin/requests/{pending[0]['id']}/approve", headers=a, json={})

    stats = (await client.get("/api/v1/admin/stats", headers=a)).json()
    assert stats["revenue_month"] == 957600  # tushum chegirmadan keyin
    codes = (await client.get("/api/v1/admin/promo-codes", headers=a)).json()
    assert codes[0]["uses"] == 1 and codes[0]["approved"] == 1
    assert codes[0]["revenue_uzs"] == 957600 and codes[0]["discount_uzs"] == 239400

    # Bitta o'qituvchi kodni ikkinchi marta ishlata olmaydi
    again = await client.post("/api/v1/teachers/me/promo-check", headers=t,
                              json={"plan_code": "standard", "months": 1, "code": "USTOZ20"})
    assert again.status_code == 422 and again.json()["error"]["code"] == "PROMO_ALREADY_USED"


async def test_amount_promo_limits_and_rules(client):
    a = await _admin(client)
    r = await _create(client, a, code="MAKTAB-5", kind="amount", value=50000, plan_code="standard", max_uses=1)
    assert r.status_code == 201, r.text
    promo_id = r.json()["id"]

    t1 = await make_teacher(client)
    t2 = await make_teacher(client)

    wrong_plan = await client.post("/api/v1/teachers/me/promo-check", headers=t1,
                                   json={"plan_code": "pro", "months": 1, "code": "maktab-5"})
    assert wrong_plan.status_code == 422 and wrong_plan.json()["error"]["code"] == "PROMO_PLAN_MISMATCH"
    assert "Standart" in wrong_plan.json()["error"]["message"]

    r = await _request(client, t1, "maktab-5")
    assert r.status_code == 201 and r.json()["amount_uzs"] == 99000 and r.json()["discount_uzs"] == 50000

    # Limit 1 — ikkinchi o'qituvchiga yetmaydi, so'rov ham yaratilmaydi
    r = await _request(client, t2, "maktab-5")
    assert r.status_code == 422 and r.json()["error"]["code"] == "PROMO_USED_UP"
    assert (await client.get("/api/v1/teachers/plans", headers=t2)).json()["requests"] == []

    # Rad etilgan so'rov limitni bo'shatadi
    req = (await client.get("/api/v1/admin/requests", headers=a)).json()[0]
    await client.post(f"/api/v1/admin/requests/{req['id']}/reject", headers=a, json={})
    assert (await _request(client, t2, "maktab-5")).status_code == 201

    # Ishlatilgan kodni o'chirib bo'lmaydi, faqat faolsizlantiriladi
    assert (await client.delete(f"/api/v1/admin/promo-codes/{promo_id}", headers=a)).status_code == 409
    r = await client.patch(f"/api/v1/admin/promo-codes/{promo_id}", headers=a, json={"is_active": False})
    assert r.json()["is_active"] is False


async def test_promo_validation_and_expiry(client):
    a = await _admin(client)
    assert (await _create(client, a, code="A B")).status_code == 422
    assert (await _create(client, a, code="KATTA", value=150)).status_code == 422
    assert (await _create(client, a, code="YOQ", plan_code="gold")).status_code == 422

    r = await _create(client, a, code="ESKI", valid_until=str(date.today() - timedelta(days=2)))
    assert r.json()["expired"] is True
    t = await make_teacher(client)
    r = await _request(client, t, "ESKI")
    assert r.status_code == 422 and r.json()["error"]["code"] == "PROMO_EXPIRED"
    r = await _request(client, t, "BORMI")
    assert r.status_code == 422 and r.json()["error"]["code"] == "PROMO_INVALID"

    # Muddatni olib tashlash — kod yana ishlaydi; so'mli chegirma narxdan oshmaydi
    esk = (await client.get("/api/v1/admin/promo-codes", headers=a)).json()[0]
    r = await client.patch(f"/api/v1/admin/promo-codes/{esk['id']}", headers=a, json={"valid_until": None})
    assert r.json()["valid_until"] is None and r.json()["expired"] is False
    big = await _create(client, a, code="BEPUL", kind="amount", value=10_000_000)
    assert big.status_code == 201
    r = await _request(client, t, "BEPUL")
    assert r.status_code == 201 and r.json()["amount_uzs"] == 0 and r.json()["discount_uzs"] == 149000

    # Ishlatilmagan kod o'chiriladi
    assert (await client.delete(f"/api/v1/admin/promo-codes/{esk['id']}", headers=a)).status_code == 204

    # Promo koddan foydalanish admin bo'lmaganlar uchun yopiq
    assert (await client.get("/api/v1/admin/promo-codes", headers=t)).status_code == 403
