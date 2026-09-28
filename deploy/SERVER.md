# Ishlab turgan server

- Manzil: https://mentorai.161-97-142-166.sslip.io (API: `/api/v1`, admin panel: `/admin`)
- Kod: `/home/root/mentorAI` (GitHub'dan klon), egasi — `mentorai` tizim foydalanuvchisi
- Sozlamalar: `/home/root/mentorAI/backend/.env` (git'da yo'q, faqat serverda)
- Rasmlar va fayllar: `/home/root/mentorAI/data/media`
- Baza: PostgreSQL 16, `mentor_ai` bazasi, `mentorai` foydalanuvchisi
- Xizmat: `systemctl status mentorai` — uvicorn, 2 jarayon (`--workers 2`), 127.0.0.1:8100
- nginx: `/etc/nginx/sites-available/mentorai` (eski nusxalar: `/root/mentorai.nginx.bak-*`), HTTPS — certbot

Serverda boshqa loyihalar ham ishlaydi (nginx saytlari, gunicorn :8000) — ularga tegilmaydi.

## Qanday ishlaydi (yuklama uchun)
- **2 jarayon**: server 2 ta CPU'dan to'liq foydalanadi. AI fon vazifalari bazadagi "ijara"
  (`ai_lease_until`) bilan olinadi — bitta ish ikki jarayonda bajarilmaydi.
- **AI limiti** tugasa ish xato bo'lmaydi: navbatda kutib (30s → 10 daqiqagacha) o'zi qayta uriniladi.
  `AI_MAX_ATTEMPTS` dan keyin ustozga "qo'lda baholang" bo'lib tushadi.
- **Rasmlar**: imzoni backend tekshiradi, faylni nginx diskdan beradi (`MEDIA_ACCEL_PREFIX`).
  Havola 1 kun davomida o'zgarmaydi, telefon rasmni xotirasida saqlaydi.
- **Reyting va progress** 30 soniya keshlanadi, baho qo'yilganda darhol yangilanadi.
- Baza ulanishlari: har jarayonda `DB_POOL_SIZE + DB_MAX_OVERFLOW` (10+10). Postgres limiti 100,
  boshqa loyihalar ham ishlatadi — jarayonlar sonini oshirsangiz buni hisobga oling.

Yuklama testi (2026-09-28, 3000 foydalanuvchilik realistik ma'lumot, tashqaridan nginx orqali):
~114 so'rov/soniya, 300 parallel foydalanuvchida xatosiz. Bunda cheklov — serverning 2 ta CPU'si.

## Yangilash
```bash
bash /home/root/mentorAI/deploy/update.sh
```

## Loglar
```bash
journalctl -u mentorai -f
```

## Zaxira nusxa (avtomatik)
- Har kuni 03:30 da baza: `/root/backups/mentorai/db_YYYY-MM-DD.dump` (14 kun saqlanadi)
- Har yakshanba fayllar: `/root/backups/mentorai/media_YYYY-MM-DD.tar.gz` (4 hafta)
- Skript: `/usr/local/bin/mentorai-backup.sh`, jadval: `/etc/cron.d/mentorai-backup`

Tiklash:
```bash
sudo -u postgres pg_restore --clean --if-exists -d mentor_ai /root/backups/mentorai/db_YYYY-MM-DD.dump
```
Zaxiralar shu serverda turibdi — server butunlay ishdan chiqsa ular ham yo'qoladi. Vaqti-vaqti
bilan boshqa joyga (kompyuter, bulut) nusxalab turing.

## Yuklama testi (qayta o'lchash uchun)
Faqat test bazasida (`mentor_test`) ishlatiladi, haqiqiy bazaga tegmaydi:
```bash
python -m tools.loadtest.seed          # 3000 foydalanuvchilik ma'lumot
python -m tools.loadtest.run --base http://127.0.0.1:8200 --concurrency 100 --duration 30
```
