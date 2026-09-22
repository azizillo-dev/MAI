"""O'qituvchi uchun AI yordamchi: "Azizillo qanday o'qiyapti?" kabi savollarga javob beradi.

Oqim: AI savolni tushunadi -> vositalarni chaqiradi (find_students, student_report...) ->
server aniq raqamlarni qaytaradi -> AI ularni qisqa, amaliy tavsiya bilan tushuntiradi.
"""

import logging
from dataclasses import dataclass, field
from typing import Any

import httpx

from app.ai.provider import AiError
from app.core.config import get_settings
from app.services.assistant_tools import TOOL_SPECS, AssistantTools

log = logging.getLogger("assistant")

MAX_TOOL_ROUNDS = 6

SYSTEM = """You are the teaching assistant inside "Mentor AI", talking to a school teacher named {teacher}.
Always reply in Uzbek (Latin script), warmly and to the point.

Rules:
- Every number (averages, counts, ranks, trends) must come from the tools. Never estimate or invent data.
- The roster below lists this teacher's groups and students with their ids. Use those ids to call
  student_report / group_report directly. Use find_students only if the name is not in the roster.
  If several students share the name, list them and ask which one. If nobody matches, say so.
- Answer in 3-8 short lines. Use "•" bullets and **bold** for key numbers. No tables, no headings.
- End with one or two concrete teaching suggestions based on the data (e.g. what to repeat, whom to talk to).
- Grades: describe results in percent and, where helpful, in the group's grading scale.
- Only discuss this teacher's students and teaching. Politely decline unrelated requests.

Roster:
{roster}"""


@dataclass
class AssistantReply:
    text: str
    attachments: list[dict[str, Any]] = field(default_factory=list)
    tool_calls: list[str] = field(default_factory=list)


class GeminiAssistant:
    def __init__(self) -> None:
        from google import genai

        s = get_settings()
        self.models = [s.gemini_model, *[m.strip() for m in s.gemini_fallback_models.split(",") if m.strip()]]
        self.client = genai.Client(api_key=s.gemini_api_key)

    async def _generate(self, contents, config, models: list[str]):
        """Javob bergan modelni qaytaradi: suhbatning keyingi bosqichlari shu model bilan davom etadi.

        429 (daqiqalik limit) har bir modelda alohida hisoblanadi — kutib o'tirmasdan zaxira modelga o'tamiz,
        faqat oxirgi model qolganda qisqa kutamiz. Aks holda o'qituvchi javobni daqiqalab kutib qoladi.
        """
        import asyncio

        from google.genai import errors

        last: Exception | None = None
        for i, model in enumerate(models):
            is_last = i == len(models) - 1
            for attempt in range(3 if is_last else 2):
                try:
                    response = await self.client.aio.models.generate_content(
                        model=model, contents=contents, config=config)
                    return response, model
                except errors.ServerError as exc:  # band: qisqa kutib qayta, keyin zaxira model
                    last = exc
                    await asyncio.sleep(1.0 * 2 ** attempt)
                except errors.ClientError as exc:
                    if exc.code == 429:
                        last = exc
                        if not is_last:
                            break
                        await asyncio.sleep(3 * 2 ** attempt)
                        continue
                    if exc.code == 404:
                        last = exc
                        break
                    raise AiError("AI so'rovni rad etdi. Savolni boshqacha yozib ko'ring") from exc
                except httpx.HTTPError as exc:
                    last = exc
                    await asyncio.sleep(1.0 * 2 ** attempt)
        raise AiError("AI hozir band. Bir daqiqadan keyin qayta so'rang") from last

    async def reply(self, tools: AssistantTools, history: list[dict[str, str]]) -> AssistantReply:
        from google.genai import types

        config = types.GenerateContentConfig(
            system_instruction=SYSTEM.format(teacher=tools.teacher.full_name, roster=await tools.roster()),
            tools=[types.Tool(function_declarations=[
                types.FunctionDeclaration(name=t["name"], description=t["description"], parameters_json_schema=t["parameters"])
                for t in TOOL_SPECS
            ])],
            # Vositalarni o'zimiz chaqiramiz: har bir chaqiruv shu ustoz doirasida ekanini nazorat qilamiz
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
            temperature=0.3,
            # Raqamlarni server hisoblaydi, AI faqat tushuntiradi: chuqur fikrlash shart emas, javob tezroq
            thinking_config=types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW),
        )
        contents: list = [
            types.Content(role="user" if m["role"] == "user" else "model", parts=[types.Part(text=m["content"])])
            for m in history
        ]
        called: list[str] = []
        models = list(self.models)
        for _ in range(MAX_TOOL_ROUNDS):
            response, used = await self._generate(contents, config, models)
            # Ishlagan model birinchi o'ringa: keyingi bosqichda limitga urilgan modelni qayta sinamaymiz
            models = [used, *[m for m in models if m != used]]
            calls = response.function_calls or []
            if not calls:
                text = (response.text or "").strip()
                if not text:
                    raise AiError("AI javob bermadi. Savolni boshqacha yozib ko'ring")
                return AssistantReply(text=text, attachments=tools.attachments, tool_calls=called)
            # Model javobini o'zgartirmay qaytaramiz (fikrlash imzolari saqlanishi shart)
            contents.append(response.candidates[0].content)
            parts = []
            for call in calls:
                called.append(call.name)
                try:
                    result = await tools.call(call.name, dict(call.args or {}))
                except Exception:
                    log.exception("Vosita xatosi: %s", call.name)
                    result = {"error": "Ma'lumotni olishda xato"}
                parts.append(types.Part.from_function_response(name=call.name, response=result))
            contents.append(types.Content(role="user", parts=parts))
        raise AiError("Savol juda murakkab bo'lib ketdi. Aniqroq so'rang (masalan, bitta o'quvchi haqida)")


class FakeAssistant:
    """Kalitsiz rejim va testlar uchun: vositalarni haqiqatan chaqiradi, javobni shablon bilan yozadi."""

    async def reply(self, tools: AssistantTools, history: list[dict[str, str]]) -> AssistantReply:
        question = history[-1]["content"]
        called = []
        for word in question.replace("?", " ").replace(",", " ").split():
            if len(word) < 3:
                continue
            found = await tools.find_students(word)
            called.append("find_students")
            if found["count"] == 1:
                r = await tools.student_report(found["matches"][0]["student_id"])
                called.append("student_report")
                avg = r["avg_percent"]
                text = (f"**{r['name']}**: o'rtacha natija **{avg if avg is not None else '—'}%**, "
                        f"holat: {r['trend']['direction']}.\n"
                        f"• Topshirmagan vazifalar: {len(r['missing_assignments'])}\n"
                        f"• Guruhdagi o'rni: {r['rank_in_group']}/{r['group_size']}")
                return AssistantReply(text=text, attachments=tools.attachments, tool_calls=called)
        groups = await tools.list_groups()
        called.append("list_groups")
        if groups["groups"]:
            g = await tools.group_report(groups["groups"][0]["group_id"])
            called.append("group_report")
            text = (f"**{g['name']}** guruhida {g['students']} o'quvchi, o'rtacha natija "
                    f"**{g['avg_percent'] if g['avg_percent'] is not None else '—'}%**.")
        else:
            text = "Hali guruhingiz yo'q. Avval guruh yarating."
        return AssistantReply(text=text, attachments=tools.attachments, tool_calls=called)


def get_assistant():
    return GeminiAssistant() if get_settings().ai_provider == "gemini" else FakeAssistant()
