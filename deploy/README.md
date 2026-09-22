# Serverga o'rnatish

Talab: Ubuntu 22.04/24.04 VPS (kamida 1 vCPU, 2 GB RAM), domen (masalan `api.mentorai.uz`).

## 1. DNS
Domen panelida `A` yozuv: `api` → server IP manzili.

## 2. Docker
```bash
curl -fsSL https://get.docker.com | sh
```

## 3. Loyihani yuklash va sozlash
```bash
git clone <repo> mentor_ai && cd mentor_ai/deploy
cp .env.production.example .env
nano .env        # DOMAIN, parollar (openssl rand -hex 32), SMTP, GEMINI_API_KEY
docker compose up -d --build
docker compose logs -f api   # "Application startup complete" chiqishi kerak
```
HTTPS sertifikatini Caddy o'zi oladi (80 va 443 portlar ochiq bo'lishi kerak).

Tekshirish: `https://DOMAIN/health` → `{"ok":true}`

## 4. Admin yaratish
```bash
docker compose exec api python -m app.cli create-admin --email admin@mentorai.uz --password 'KUCHLI-PAROL' --name "Bosh Admin"
```
Admin panel: `https://DOMAIN/admin`

## 5. Ilova (APK)
```bash
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://DOMAIN/api/v1
```

## Yangilash
```bash
git pull && cd deploy && docker compose up -d --build
```
Migratsiyalar konteyner ishga tushganda avtomatik qo'llanadi.

## Zaxira nusxa
```bash
docker compose exec db pg_dump -U mentor mentor_ai | gzip > backup_$(date +%F).sql.gz
```
Rasmlar `media` volume'ida: `docker run --rm -v deploy_media:/m -v $PWD:/b alpine tar czf /b/media.tgz -C /m .`
