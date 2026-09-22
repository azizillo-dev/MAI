# Ishlab turgan server

- Manzil: https://mentorai.161-97-142-166.sslip.io (API: `/api/v1`, admin panel: `/admin`)
- Kod: `/home/root/mentorAI` (GitHub'dan klon), egasi — `mentorai` tizim foydalanuvchisi
- Sozlamalar: `/home/root/mentorAI/backend/.env` (git'da yo'q, faqat serverda)
- Rasmlar va fayllar: `/home/root/mentorAI/data/media`
- Baza: PostgreSQL 16, `mentor_ai` bazasi, `mentorai` foydalanuvchisi
- Xizmat: `systemctl status mentorai` (uvicorn, 127.0.0.1:8100)
- nginx: `/etc/nginx/sites-available/mentorai`, HTTPS — certbot (avtomatik yangilanadi)

Serverda boshqa loyihalar ham ishlaydi (nginx saytlari, gunicorn :8000) — ularga tegilmaydi.

## Yangilash
```bash
bash /home/root/mentorAI/deploy/update.sh
```

## Loglar
```bash
journalctl -u mentorai -f
```

## Zaxira nusxa
```bash
sudo -u postgres pg_dump mentor_ai | gzip > /root/mentor_ai_$(date +%F).sql.gz
```
