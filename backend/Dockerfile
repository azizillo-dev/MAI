FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app

# Rasm va PDF'lar shu yerda saqlanadi (docker-compose'da volume)
ENV MEDIA_ROOT=/data/media
RUN useradd --create-home --uid 1000 mentor && mkdir -p /data/media && chown -R mentor /data
USER mentor

EXPOSE 8000

# Har ishga tushishda migratsiyalar qo'llanadi, keyin API. Bitta worker: fon vazifalari jarayon ichida ishlaydi
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'"]
