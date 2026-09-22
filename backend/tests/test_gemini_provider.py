"""GeminiProvider: tarmoqqa chiqmasdan, SDK javobini soxtalashtirib tekshiriladi."""

from types import SimpleNamespace

import pytest
from google.genai import errors, types

from app.ai import provider as ai
from app.ai.schemas import GradedItem, GradeResult


def _response(parsed, finish="STOP", blocked=None):
    return SimpleNamespace(
        parsed=parsed,
        usage_metadata=SimpleNamespace(
            prompt_token_count=1200, candidates_token_count=150, thoughts_token_count=300, cached_content_token_count=800
        ),
        prompt_feedback=SimpleNamespace(block_reason=blocked) if blocked else None,
        candidates=[SimpleNamespace(finish_reason=types.FinishReason[finish])],
    )


@pytest.fixture
def gemini(monkeypatch):
    monkeypatch.setattr(ai.get_settings(), "gemini_api_key", "test-key")
    p = ai.GeminiProvider()
    p.retry_base_seconds = 0  # testlarda kutmaymiz
    calls = []

    def install(*results):
        queue = list(results)

        async def fake_generate(*, model, contents, config):
            calls.append({"model": model, "contents": contents, "config": config})
            result = queue.pop(0) if len(queue) > 1 else queue[0]
            if isinstance(result, Exception):
                raise result
            return result

        monkeypatch.setattr(p.client.aio.models, "generate_content", fake_generate)

    return p, install, calls


CTX = ai.GradingContext(
    teacher_context="O'qituvchi: Ali Valiyev.", subject="math", grading_scale="5", title="Kasrlar",
    instructions=None, items=[{"number": "1", "text": "1/2+1/4", "answer": "3/4"}],
)
GOOD = GradeResult(
    matches_assignment=True, items=[GradedItem(number="1", verdict="correct", comment="")],
    score_percent=100, feedback_student="Zo'r!", note_teacher="Yaxshi", confidence=0.95,
)


async def test_grade_success_and_usage(gemini):
    p, install, calls = gemini
    install(_response(GOOD))
    result, usage = await p.grade(CTX, [ai.Image(b"\xff\xd8\xff...", "image/jpeg")], None)
    assert result.score_percent == 100
    assert usage.provider == "gemini" and usage.input_tokens == 1200
    assert usage.output_tokens == 450 and usage.cache_read_tokens == 800  # fikrlash tokenlari ham hisoblanadi
    cfg = calls[0]["config"]
    assert cfg.response_schema is GradeResult and cfg.response_mime_type == "application/json"
    assert "Kasrlar" in cfg.system_instruction  # vazifa konteksti o'zgarmas qismda (kesh uchun)


async def test_rate_limit_becomes_ai_error(gemini):
    p, install, calls = gemini
    install(errors.ClientError(429, {"error": {"message": "Resource exhausted"}}))
    with pytest.raises(ai.AiError, match="limiti"):
        await p.grade(CTX, [], "javob")
    assert len(calls) == 4  # 3 marta kutib qayta urindi


async def test_busy_model_retries_then_falls_back(gemini):
    p, install, calls = gemini
    busy = errors.ServerError(503, {"error": {"message": "high demand"}})
    install(busy, busy, busy, busy, _response(GOOD))
    result, usage = await p.grade(CTX, [], "javob")
    assert result.score_percent == 100
    assert [c["model"] for c in calls] == [p.model] * 4 + [p.fallback_models[0]]
    assert usage.model == p.fallback_models[0]


async def test_transient_503_recovers_on_same_model(gemini):
    p, install, calls = gemini
    install(errors.ServerError(503, {"error": {"message": "busy"}}), _response(GOOD))
    _, usage = await p.grade(CTX, [], "javob")
    assert len(calls) == 2 and usage.model == p.model


async def test_safety_block_and_truncation(gemini):
    p, install, _ = gemini
    install(_response(None, blocked="SAFETY"))
    with pytest.raises(ai.AiError, match="bosh tortdi"):
        await p.grade(CTX, [], "javob")
    install(_response(None, finish="MAX_TOKENS"))
    with pytest.raises(ai.AiError, match="to'liq"):
        await p.grade(CTX, [], "javob")


async def test_pdf_is_sent_as_document_part(gemini):
    p, install, calls = gemini
    install(_response(ai.ExtractedItems(items=[], notes=None)))
    await p.extract_from_pdf(b"%PDF-1.7 ...", "math", "56-60")
    part = calls[0]["contents"][0]
    assert part.inline_data.mime_type == "application/pdf"
    assert "56-60" in calls[0]["contents"][1]
