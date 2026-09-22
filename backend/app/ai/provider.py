"""AI provayderlari.

- GeminiProvider: Google Gemini. `AI_PROVIDER=gemini` va GEMINI_API_KEY bo'lganda (bepul tarif bor).
- AnthropicProvider: Claude. `AI_PROVIDER=anthropic` va ANTHROPIC_API_KEY bo'lganda.
- FakeProvider: kalitsiz ishlab chiqish va testlar uchun. Natijalari barqaror (tasodifiy emas).

Ikkalasi bir xil interfeysga ega, shuning uchun qolgan kod qaysi biri ishlayotganini bilmaydi.
"""

import asyncio
import base64
import time
from dataclasses import dataclass, field
from typing import Protocol

import anthropic
import httpx

from app.ai import prompts
from app.ai.schemas import ExtractedItem, ExtractedItems, GradedItem, GradeResult, Rubric, RubricCriterion
from app.core.config import get_settings


class AiError(Exception):
    """AI javob bera olmadi (tarmoq, limit, rad etish). Xabar ustozga ko'rsatiladi."""


@dataclass
class Usage:
    provider: str
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read_tokens: int = 0
    cache_write_tokens: int = 0
    duration_ms: int = 0


@dataclass
class Image:
    data: bytes
    mime: str


@dataclass
class GradingContext:
    """Bitta vazifa uchun hamma o'quvchilarga bir xil: kesh (prompt caching) shu qismga qo'yiladi."""

    teacher_context: str
    subject: str
    grading_scale: str
    title: str
    instructions: str | None
    items: list[dict] = field(default_factory=list)
    rubric: list[dict] = field(default_factory=list)
    feedback_language: str = "uz"


class AiProvider(Protocol):
    async def extract_from_pdf(self, pdf: bytes, subject: str, problems_hint: str | None) -> tuple[ExtractedItems, Usage]: ...

    async def extract_from_images(self, images: list[Image], subject: str) -> tuple[ExtractedItems, Usage]: ...

    async def build_rubric(self, title: str, instructions: str, subject: str) -> tuple[Rubric, Usage]: ...

    async def grade(
        self, ctx: GradingContext, work: list[Image], text_answer: str | None
    ) -> tuple[GradeResult, Usage]: ...


def _image_block(img: Image) -> dict:
    return {
        "type": "image",
        "source": {"type": "base64", "media_type": img.mime, "data": base64.standard_b64encode(img.data).decode()},
    }


class AnthropicProvider:
    def __init__(self) -> None:
        s = get_settings()
        self.model = s.ai_model
        # Kalit ANTHROPIC_API_KEY (yoki `ant auth login` profili) dan olinadi
        self.client = anthropic.AsyncAnthropic(timeout=180.0, max_retries=3)

    async def _parse(self, *, system: list[dict], content: list[dict], output_format, effort: str):
        started = time.monotonic()
        try:
            response = await self.client.messages.parse(
                model=self.model,
                max_tokens=16000,
                thinking={"type": "adaptive"},
                output_config={"effort": effort},
                system=system,
                messages=[{"role": "user", "content": content}],
                output_format=output_format,
            )
        except anthropic.RateLimitError as exc:
            raise AiError("AI hozir band. Birozdan keyin avtomatik qayta uriniladi") from exc
        except anthropic.APIStatusError as exc:
            raise AiError(f"AI xizmati xatosi ({exc.status_code})") from exc
        except anthropic.APIConnectionError as exc:
            raise AiError("AI xizmatiga ulanib bo'lmadi") from exc

        u = response.usage
        usage = Usage(
            provider="anthropic",
            model=self.model,
            input_tokens=u.input_tokens,
            output_tokens=u.output_tokens,
            cache_read_tokens=u.cache_read_input_tokens or 0,
            cache_write_tokens=u.cache_creation_input_tokens or 0,
            duration_ms=int((time.monotonic() - started) * 1000),
        )
        if response.stop_reason == "refusal":
            raise AiError("AI bu materialni qayta ishlashdan bosh tortdi. Ustoz qo'lda tekshiradi")
        if response.stop_reason == "max_tokens" or response.parsed_output is None:
            raise AiError("AI javobi to'liq kelmadi")
        return response.parsed_output, usage

    async def extract_from_pdf(self, pdf, subject, problems_hint):
        content = [
            {
                "type": "document",
                "source": {"type": "base64", "media_type": "application/pdf", "data": base64.standard_b64encode(pdf).decode()},
            },
            {"type": "text", "text": prompts.extract_request(subject, problems_hint)},
        ]
        return await self._parse(
            system=[{"type": "text", "text": prompts.EXTRACT_SYSTEM}], content=content, output_format=ExtractedItems, effort="high"
        )

    async def extract_from_images(self, images, subject):
        content = [*(_image_block(i) for i in images), {"type": "text", "text": prompts.extract_request(subject, None)}]
        return await self._parse(
            system=[{"type": "text", "text": prompts.EXTRACT_SYSTEM}], content=content, output_format=ExtractedItems, effort="high"
        )

    async def build_rubric(self, title, instructions, subject):
        content = [{"type": "text", "text": prompts.rubric_request(title, instructions, subject)}]
        return await self._parse(
            system=[{"type": "text", "text": prompts.RUBRIC_SYSTEM}], content=content, output_format=Rubric, effort="medium"
        )

    async def grade(self, ctx, work, text_answer):
        system = [
            {"type": "text", "text": prompts.GRADE_SYSTEM},
            # Vazifa konteksti hamma o'quvchilar uchun bir xil: keshlanadi, 2-o'quvchidan boshlab arzonroq
            {"type": "text", "text": prompts.grading_context(ctx), "cache_control": {"type": "ephemeral"}},
        ]
        content = [*(_image_block(i) for i in work)]
        content.append({"type": "text", "text": prompts.grade_request(text_answer, len(work))})
        return await self._parse(system=system, content=content, output_format=GradeResult, effort="high")


class GeminiProvider:
    """Google Gemini (google-genai SDK). AI Studio kaliti bilan bepul tarifda ham ishlaydi.

    Gemini takrorlanuvchi prefiksni o'zi keshlaydi (implicit caching), shuning uchun o'zgarmas qism
    (ko'rsatma + vazifa konteksti) system_instruction'da, o'quvchi ishi esa oxirida turadi.
    """

    def __init__(self) -> None:
        from google import genai  # faqat gemini tanlanganda yuklanadi

        s = get_settings()
        self.model = s.gemini_model
        self.fallback_models = [m.strip() for m in s.gemini_fallback_models.split(",") if m.strip()]
        self.retry_base_seconds = 2.0
        self.client = genai.Client(api_key=s.gemini_api_key)

    async def _generate(self, *, system: str, parts: list, schema, thinking: bool = True):
        from google.genai import types

        started = time.monotonic()
        config = types.GenerateContentConfig(
            system_instruction=system,
            response_mime_type="application/json",
            response_schema=schema,
            temperature=0.2,  # baholash barqaror bo'lishi uchun
            max_output_tokens=16000,
            # Fikrlash (thinking) murakkab qo'lyozmani tekshirishda aniqlikni oshiradi
            thinking_config=types.ThinkingConfig(thinking_budget=-1 if thinking else 0),
        )
        response, model_used = await self._call_with_retry(parts, config)

        u = response.usage_metadata
        usage = Usage(
            provider="gemini",
            model=model_used,
            input_tokens=(u.prompt_token_count or 0) if u else 0,
            output_tokens=((u.candidates_token_count or 0) + (u.thoughts_token_count or 0)) if u else 0,
            cache_read_tokens=(u.cached_content_token_count or 0) if u else 0,
            duration_ms=int((time.monotonic() - started) * 1000),
        )
        if response.prompt_feedback and response.prompt_feedback.block_reason:
            raise AiError("AI bu materialni qayta ishlashdan bosh tortdi. Ustoz qo'lda tekshiradi")
        finish = response.candidates[0].finish_reason if response.candidates else None
        if finish is not None and finish.name == "MAX_TOKENS":
            raise AiError("AI javobi to'liq kelmadi")
        if finish is not None and finish.name not in ("STOP", "FINISH_REASON_UNSPECIFIED"):
            raise AiError("AI bu materialni qayta ishlashdan bosh tortdi. Ustoz qo'lda tekshiradi")
        parsed = response.parsed
        if not isinstance(parsed, schema):
            raise AiError("AI javobini o'qib bo'lmadi")
        return parsed, usage

    async def _call_with_retry(self, parts: list, config):
        """Band (503/500) yoki vaqtinchalik limit (429) bo'lsa kutib qayta urinadi, keyin zaxira modelga o'tadi.

        Bepul tarifda model tez-tez "band" bo'ladi: bir urinishda taslim bo'lsak, ish ustozga qo'lda
        tekshirish uchun tushib qolardi.
        """
        from google.genai import errors

        last: Exception | None = None
        for model in [self.model, *self.fallback_models]:
            for attempt in range(4):
                try:
                    response = await self.client.aio.models.generate_content(model=model, contents=parts, config=config)
                    return response, model  # qaysi model javob bergani xarajat hisobiga yoziladi
                except errors.ClientError as exc:
                    last = exc
                    if exc.code == 429 and attempt < 3:
                        await asyncio.sleep(self.retry_base_seconds * 2 ** (attempt + 1))
                        continue
                    if exc.code == 404:  # model nomi eskirgan: keyingisiga o'tamiz
                        break
                    if exc.code == 429:
                        raise AiError("AI limiti tugadi (daqiqa/kunlik). Birozdan keyin qayta urinib ko'ring") from exc
                    if exc.code in (400, 403) and "API key" in str(exc):
                        raise AiError("Gemini API kaliti noto'g'ri yoki faol emas") from exc
                    raise AiError(f"AI so'rovi rad etildi ({exc.code})") from exc
                except errors.ServerError as exc:
                    last = exc
                    if attempt < 3:
                        await asyncio.sleep(self.retry_base_seconds * 2 ** attempt)
                        continue
                    break  # bu model band: zaxira modelga o'tamiz
                except errors.APIError as exc:
                    raise AiError(f"AI xizmati xatosi ({exc.code})") from exc
                except httpx.HTTPError as exc:
                    last = exc
                    if attempt < 3:
                        await asyncio.sleep(self.retry_base_seconds * 2 ** attempt)
                        continue
                    raise AiError("AI xizmatiga ulanib bo'lmadi") from exc
        code = getattr(last, "code", None)
        raise AiError(f"AI hozir band ({code}). Keyinroq qayta urinib ko'ring") from last

    @staticmethod
    def _image(img: Image):
        from google.genai import types

        return types.Part.from_bytes(data=img.data, mime_type=img.mime)

    async def extract_from_pdf(self, pdf, subject, problems_hint):
        from google.genai import types

        parts = [types.Part.from_bytes(data=pdf, mime_type="application/pdf"), prompts.extract_request(subject, problems_hint)]
        return await self._generate(system=prompts.EXTRACT_SYSTEM, parts=parts, schema=ExtractedItems)

    async def extract_from_images(self, images, subject):
        parts = [*(self._image(i) for i in images), prompts.extract_request(subject, None)]
        return await self._generate(system=prompts.EXTRACT_SYSTEM, parts=parts, schema=ExtractedItems)

    async def build_rubric(self, title, instructions, subject):
        return await self._generate(
            system=prompts.RUBRIC_SYSTEM,
            parts=[prompts.rubric_request(title, instructions, subject)],
            schema=Rubric,
            thinking=False,
        )

    async def grade(self, ctx, work, text_answer):
        system = prompts.GRADE_SYSTEM + "\n\n" + prompts.grading_context(ctx)
        parts = [*(self._image(i) for i in work), prompts.grade_request(text_answer, len(work))]
        return await self._generate(system=system, parts=parts, schema=GradeResult)


class FakeProvider:
    """Kalitsiz rejim: interfeys va oqimni sinash uchun. Hech qachon haqiqiy baho sifatida ishlatilmaydi."""

    def _usage(self) -> Usage:
        return Usage(provider="fake", model="fake", input_tokens=1000, output_tokens=200, duration_ms=5)

    async def extract_from_pdf(self, pdf, subject, problems_hint):
        numbers = _expand_hint(problems_hint) or ["1", "2", "3"]
        items = [ExtractedItem(number=n, text=f"{n}-misol sharti (namuna)", answer=None) for n in numbers[:30]]
        return ExtractedItems(items=items, notes="Namuna rejimi: haqiqiy AI ulanmagan"), self._usage()

    async def extract_from_images(self, images, subject):
        items = [ExtractedItem(number=str(i + 1), text=f"Rasmdagi {i + 1}-misol (namuna)", answer=None) for i in range(3)]
        return ExtractedItems(items=items, notes="Namuna rejimi: haqiqiy AI ulanmagan"), self._usage()

    async def build_rubric(self, title, instructions, subject):
        return Rubric(
            criteria=[
                RubricCriterion(name="Vazifaga mosligi", weight=40, description="Topshiriq talablari bajarilgan"),
                RubricCriterion(name="To'g'riligi", weight=40, description="Mazmun va javoblar to'g'ri"),
                RubricCriterion(name="Rasmiylashtirish", weight=20, description="Toza va tartibli"),
            ]
        ), self._usage()

    async def grade(self, ctx, work, text_answer):
        numbers = [str(i.get("number")) for i in ctx.items] or [c["name"] for c in ctx.rubric] or ["1"]
        graded = [
            GradedItem(number=n, verdict="correct" if k % 4 else "partial", comment="" if k % 4 else "Hisobda kichik xato")
            for k, n in enumerate(numbers, start=1)
        ]
        return GradeResult(
            matches_assignment=True,
            items=graded,
            score_percent=85,
            feedback_student="Yaxshi ish! Bitta misolda hisobni qayta tekshiring.",
            note_teacher="Umuman yaxshi, hisoblashda shoshilyapti.",
            confidence=0.9,
        ), self._usage()


def _expand_hint(hint: str | None) -> list[str]:
    """"56-60, 63" -> ["56","57","58","59","60","63"] (faqat fake rejim uchun)."""
    if not hint:
        return []
    out: list[str] = []
    for part in hint.replace(" ", "").split(","):
        if "-" in part:
            a, _, b = part.partition("-")
            if a.isdigit() and b.isdigit() and int(b) >= int(a):
                out += [str(n) for n in range(int(a), min(int(b), int(a) + 50) + 1)]
        elif part:
            out.append(part)
    return out


_provider: AiProvider | None = None


def get_provider() -> AiProvider:
    global _provider
    if _provider is None:
        name = get_settings().ai_provider
        _provider = {"gemini": GeminiProvider, "anthropic": AnthropicProvider}.get(name, FakeProvider)()
    return _provider
