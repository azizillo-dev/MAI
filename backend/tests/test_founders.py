import io

from PIL import Image

from tests.conftest import make_teacher
from tests.test_billing_email import _admin


def _photo(w=900, h=1200, color=(200, 120, 60)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (w, h), color).save(buf, "PNG")
    return buf.getvalue()


async def test_founders_managed_by_admin_and_shown_on_site(client):
    a = await _admin(client)
    r = await client.post("/api/v1/admin/founders", headers=a,
                          json={"name": "Azizillo", "role": "Founder, Backend Engineer", "bio": "G'oya muallifi"})
    assert r.status_code == 201, r.text
    first = r.json()
    assert first["photo_url"] is None
    second = (await client.post("/api/v1/admin/founders", headers=a,
                                json={"name": "Sherik", "role": "Mobile Developer"})).json()

    # Rasm: kvadrat 480px JPEG bo'lib saqlanadi, havolada versiya bor
    r = await client.post(f"/api/v1/admin/founders/{first['id']}/photo", headers=a,
                          files={"file": ("me.png", _photo(), "image/png")})
    assert r.status_code == 200, r.text
    url = r.json()["photo_url"]
    assert url.startswith(f"/api/v1/site/founders/{first['id']}/photo?v=")
    img = await client.get(url)
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"
    assert "immutable" in img.headers["cache-control"]
    assert Image.open(io.BytesIO(img.content)).size == (480, 480)

    # Saytda (ochiq API) tartib bilan chiqadi; tartibni o'zgartirish
    public = (await client.get("/api/v1/site/public")).json()["founders"]
    assert [f["name"] for f in public] == ["Azizillo", "Sherik"]
    await client.post(f"/api/v1/admin/founders/{second['id']}/move/up", headers=a)
    public = (await client.get("/api/v1/site/public")).json()["founders"]
    assert [f["name"] for f in public] == ["Sherik", "Azizillo"]
    assert "photo" not in public[1]  # base64 ma'lumot ochiq javobga chiqmaydi

    r = await client.patch(f"/api/v1/admin/founders/{second['id']}", headers=a, json={"role": "Flutter Developer"})
    assert r.json()["role"] == "Flutter Developer"
    assert (await client.delete(f"/api/v1/admin/founders/{second['id']}", headers=a)).status_code == 204
    assert [f["name"] for f in (await client.get("/api/v1/admin/founders", headers=a)).json()] == ["Azizillo"]


async def test_founders_validation_and_permissions(client):
    a = await _admin(client)
    t = await make_teacher(client)
    assert (await client.post("/api/v1/admin/founders", headers=t, json={"name": "X Y", "role": "CEO"})).status_code == 403
    assert (await client.post("/api/v1/admin/founders", headers=a, json={"name": "A", "role": "CEO"})).status_code == 422
    f = (await client.post("/api/v1/admin/founders", headers=a, json={"name": "Ali Vali", "role": "CEO"})).json()
    bad = await client.post(f"/api/v1/admin/founders/{f['id']}/photo", headers=a,
                            files={"file": ("x.png", b"bu rasm emas", "image/png")})
    assert bad.status_code == 422 and bad.json()["error"]["code"] == "PHOTO_INVALID"
    assert (await client.get("/api/v1/site/founders/yoq/photo")).status_code == 404
    assert (await client.get(f"/api/v1/site/founders/{f['id']}/photo")).status_code == 404  # rasm yuklanmagan
