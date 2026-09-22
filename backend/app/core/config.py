from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: Literal["development", "production", "test"] = "development"
    database_url: str = "postgresql+asyncpg://mentor:mentor@localhost:5432/mentor_ai"

    jwt_secret: str = "dev-jwt-secret-only-for-local-development-000"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 60
    registration_token_minutes: int = 20

    otp_secret: str = "dev-otp-secret-only-for-local-development-000"
    otp_length: int = 6
    otp_ttl_seconds: int = 180
    otp_resend_seconds: int = 60
    otp_max_attempts: int = 5
    otp_max_per_phone_hour: int = 5
    otp_max_per_ip_hour: int = 20
    otp_dev_echo: bool = False

    # disabled: SMS provayder ulanmagan — faqat email orqali kirish ishlaydi
    sms_provider: Literal["console", "eskiz", "disabled"] = "console"
    eskiz_email: str = ""
    eskiz_password: str = ""
    eskiz_from: str = "4546"
    eskiz_base_url: str = "https://notify.eskiz.uz/api"

    # Email orqali kod: console (development) | smtp (Gmail va boshqalar)
    email_provider: Literal["console", "smtp"] = "console"
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    email_from_name: str = "Mentor AI"

    # Yangi o'qituvchi uchun bepul sinov muddati
    trial_days: int = 14

    join_max_failed_attempts: int = 5
    join_lock_minutes: int = 15

    public_join_url: str = "https://mentorai.uz/join"

    # Fayllar (PDF kitoblar, vazifa rasmlari, o'quvchi ishlari)
    media_root: str = "media"
    # Imzolangan havolalar shu manzil bilan beriladi (telefon yuklab olishi uchun)
    public_api_url: str = "http://10.0.2.2:8000"
    media_url_ttl_seconds: int = 3600
    max_image_mb: int = 10
    max_pdf_mb: int = 60
    max_images_per_submission: int = 10

    # AI: "gemini" (Google, bepul tarif bor), "anthropic" (Claude) yoki "fake" (kalitsiz sinash uchun)
    ai_provider: Literal["gemini", "anthropic", "fake"] = "fake"
    ai_model: str = "claude-opus-5"
    # https://aistudio.google.com/apikey dan olinadi
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.6-flash"
    # Asosiy model band bo'lsa navbat bilan sinaladi (vergul bilan)
    # Har bir modelning bepul limiti alohida: biri tugasa keyingisi ishlaydi
    gemini_fallback_models: str = "gemini-3.5-flash,gemini-3.8-flash,gemini-flash-latest,gemini-3.5-flash-lite"
    # Shu ishonchdan past natija o'quvchiga chiqmaydi, avval ustoz ko'radi
    ai_min_confidence: float = 0.7
    # Kitobdan bir vazifaga olinadigan maksimal sahifalar (xarajat va sifat uchun)
    max_book_pages_per_assignment: int = 15

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @model_validator(mode="after")
    def _check_production_secrets(self) -> "Settings":
        if self.is_production:
            if self.jwt_secret.startswith("dev-") or self.otp_secret.startswith("dev-"):
                raise ValueError("JWT_SECRET va OTP_SECRET production uchun o'rnatilishi shart")
            if self.otp_dev_echo:
                raise ValueError("OTP_DEV_ECHO production'da yoqilishi mumkin emas")
            if self.sms_provider == "console":
                raise ValueError("Production'da SMS_PROVIDER=eskiz yoki disabled bo'lishi kerak")
            if self.email_provider == "console":
                raise ValueError("Production'da EMAIL_PROVIDER=smtp bo'lishi kerak")
            if self.ai_provider == "fake":
                raise ValueError("Production'da AI_PROVIDER=gemini yoki anthropic bo'lishi kerak")
        if self.ai_provider == "gemini" and not self.gemini_api_key:
            raise ValueError("AI_PROVIDER=gemini uchun GEMINI_API_KEY kerak (https://aistudio.google.com/apikey)")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
