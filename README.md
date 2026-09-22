# Mentor AI

Uy vazifalarini AI yordamida tekshiruvchi platforma. Rollar: o'qituvchi, o'quvchi, admin.

```
backend/   Python · FastAPI · SQLAlchemy 2 (async) · PostgreSQL · Alembic
mobile/    Flutter (Android) · Riverpod · go_router · Dio
```

## Hozir tayyor bo'lgan qism

| Oqim | Tafsilot |
|---|---|
| Ro'yxatdan o'tish / kirish | Telefon → SMS kod (Eskiz.uz) → yangi bo'lsa ma'lumotlar, bor bo'lsa darhol kirish |
| O'quvchi | Ism, familiya, otasining ismi, tug'ilgan sana, jins → tasdiqlash oynasi → **qulflanadi** |
| O'qituvchi | Ism, familiya → AI uchun 7 ta savol (fan, o'quvchilar, dars joyi, baholash tizimi, tekshiruv uslubi, izoh tili, qo'shimcha) → `ai_context` |
| Guruh | Yaratish (tarif limiti bilan), kod `K7M-4XQ` + 6 xonali parol, QR, "Ulashish", parolni yangilash, tasdiqlash rejimi |
| Guruhga qo'shilish | Kod → guruhni ko'rib tasdiqlash → parol; yoki QR/havola (parolsiz); 5 marta xato → 15 daqiqa blok |
| Profilni qulflash | O'qituvchi "tahrirlashga ruxsat" beradi → o'quvchi **1 marta** o'zgartiradi → yana qulflanadi (o'zgarishlar tarixi saqlanadi) |
| Tariflar | Free: 1 guruh / 30 o'quvchi / haftasiga 4 vazifa; Pro: 3 guruh / 90 o'quvchi. Limitlar `plans` jadvalida, kodda emas |
| Xavfsizlik | OTP HMAC-xesh, qayta yuborish 60 s, soatiga 5 ta; refresh token rotatsiyasi + o'g'irlanganini aniqlash; logout darhol kuchga kiradi |

## Ishlab chiqish muhiti (D:\dev)

| Vosita | Joyi |
|---|---|
| Flutter 3.47.5 | `D:\dev\flutter` |
| JDK 21 | `D:\dev\jdk` |
| Android SDK, NDK, emulyator | `D:\dev\android-sdk` |
| Gradle / pub / AVD keshlari | `D:\dev\cache\...` (C: diskni to'ldirmaslik uchun) |

`PATH`, `JAVA_HOME`, `ANDROID_HOME`, `GRADLE_USER_HOME`, `PUB_CACHE`, `ANDROID_AVD_HOME` foydalanuvchi
o'zgaruvchilarida sozlangan (yangi terminal ochilganda ishlaydi). Emulyator: `emulator -avd mentor_pixel`.

## AI

`.env` da `AI_PROVIDER=fake` bo'lsa, AI namunaviy natija qaytaradi (kalitsiz sinash uchun).
Haqiqiy tekshiruv uchun: `AI_PROVIDER=anthropic` va `ANTHROPIC_API_KEY=...` (model: `claude-opus-5`).
Har bir AI chaqiruvi (`ai_runs` jadvali) token va vaqt bilan yoziladi — admin paneldagi xarajat hisoboti uchun.

## Backend

```bash
cd backend
python -m venv .venv && .venv/Scripts/activate      # Linux/macOS: source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env                                  # DATABASE_URL, JWT_SECRET, OTP_SECRET ni to'ldiring
createdb mentor_ai                                    # yoki pgAdmin orqali
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- API hujjati: http://localhost:8000/docs
- Testlar: `pytest` (SQLite xotirada, PostgreSQL shart emas)
- Development rejimida SMS yuborilmaydi: kod konsolga chiqadi va `OTP_DEV_ECHO=true` bo'lsa ilovada ko'rinadi.
- Production'da `ENVIRONMENT=production` qo'yilsa, dev sozlamalar bilan server ishga tushmaydi (himoya).

## Mobil ilova

```bash
cd mobile
flutter pub get
flutter run                                           # emulyator: backend 10.0.2.2:8000 da
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api/v1   # haqiqiy telefon
flutter build apk --release --dart-define=API_BASE_URL=https://api.mentorai.uz/api/v1
```

### Silliqlik (120 Hz)

- `flutter_displaymode` ilova ochilishida 90/120 Hz rejimni yoqadi (aks holda ko'p Android'larda 60 Hz).
- Impeller renderer (Flutter standarti), `const` widgetlar, `ListView.builder`/`SliverList.builder` (lazy).
- Tablar `StatefulShellRoute.indexedStack`: tab almashganda qayta yuklanmaydi, scroll joyida qoladi.
- Sessiya keshda: ilova internet bo'lmasa ham darhol ochiladi, fonda yangilanadi.
- Profil rejimida arzon telefonda tekshirish: `flutter run --profile`.

### Guruh havolalari (App Links)

QR va "Ulashish" dagi havola: `https://mentorai.uz/join/K7M4XQ?t=TOKEN`.
Ilova to'g'ridan-to'g'ri ochilishi uchun domenda `/.well-known/assetlinks.json` joylashtirish kerak
(ilova imzosining SHA-256 barmoq izi bilan). Busiz ham QR skaner ilova ichida ishlaydi.
