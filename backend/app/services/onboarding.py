"""O'qituvchini AI o'rganishi uchun savollar.

Savollar serverda turadi, ilova ularni dinamik chizadi. Shunday qilib savolni o'zgartirish
yoki qo'shish uchun ilovani Play Market'da yangilash shart emas.
Javoblardan `ai_context` matni yig'iladi va vazifa tekshiruvchi AI prompt'iga qo'shiladi.
"""

from typing import Any

from app.core.errors import AppError

Localized = dict[str, str]

QUESTIONS: list[dict[str, Any]] = [
    {
        "id": "subjects",
        "type": "multi",
        "required": True,
        "icon": "book",
        "title": {"uz": "Qaysi fandan dars berasiz?", "ru": "Какой предмет вы преподаёте?"},
        "hint": {"uz": "Bir nechtasini tanlashingiz mumkin", "ru": "Можно выбрать несколько"},
        "options": [
            {"id": "math", "label": {"uz": "Matematika", "ru": "Математика"}},
            {"id": "english", "label": {"uz": "Ingliz tili", "ru": "Английский язык"}},
        ],
    },
    {
        "id": "student_levels",
        "type": "multi",
        "required": True,
        "icon": "users",
        "title": {"uz": "O'quvchilaringiz kimlar?", "ru": "Кто ваши ученики?"},
        "hint": {"uz": "AI tekshiruvda yoshga mos til ishlatadi", "ru": "ИИ подберёт язык под возраст"},
        "options": [
            {"id": "grade_1_4", "label": {"uz": "1–4-sinf", "ru": "1–4 класс"}},
            {"id": "grade_5_9", "label": {"uz": "5–9-sinf", "ru": "5–9 класс"}},
            {"id": "grade_10_11", "label": {"uz": "10–11-sinf", "ru": "10–11 класс"}},
            {"id": "applicants", "label": {"uz": "Abituriyentlar", "ru": "Абитуриенты"}},
            {"id": "adults", "label": {"uz": "Kattalar", "ru": "Взрослые"}},
        ],
    },
    {
        "id": "teaching_place",
        "type": "single",
        "required": True,
        "icon": "building",
        "title": {"uz": "Qayerda dars berasiz?", "ru": "Где вы преподаёте?"},
        "options": [
            {"id": "school", "label": {"uz": "Maktab", "ru": "Школа"}},
            {"id": "learning_center", "label": {"uz": "O'quv markazi", "ru": "Учебный центр"}},
            {"id": "private", "label": {"uz": "Xususiy (repetitor)", "ru": "Репетитор"}},
            {"id": "online", "label": {"uz": "Onlayn", "ru": "Онлайн"}},
        ],
    },
    {
        "id": "grading_scale",
        "type": "single",
        "required": True,
        "icon": "star",
        "title": {"uz": "Qaysi baholash tizimidan foydalanasiz?", "ru": "Какую шкалу оценок используете?"},
        "hint": {"uz": "Har bir guruh uchun keyin alohida o'zgartirish mumkin", "ru": "Можно изменить для каждой группы"},
        "options": [
            {"id": "5", "label": {"uz": "5 ballik", "ru": "5-балльная"}},
            {"id": "10", "label": {"uz": "10 ballik", "ru": "10-балльная"}},
            {"id": "100", "label": {"uz": "100 ballik", "ru": "100-балльная"}},
        ],
    },
    {
        "id": "checking_style",
        "type": "single",
        "required": True,
        "icon": "scale",
        "title": {"uz": "Vazifalarni qanday tekshirasiz?", "ru": "Как вы проверяете работы?"},
        "options": [
            {
                "id": "lenient",
                "label": {"uz": "Yumshoq", "ru": "Мягко"},
                "description": {"uz": "Yo'l to'g'ri bo'lsa, kichik xatolarga ko'z yumaman", "ru": "Если ход верный, мелкие ошибки прощаю"},
            },
            {
                "id": "balanced",
                "label": {"uz": "Muvozanatli", "ru": "Сбалансированно"},
                "description": {"uz": "Qisman to'g'ri yechimga qisman ball beraman", "ru": "За частично верное решение — часть балла"},
            },
            {
                "id": "strict",
                "label": {"uz": "Qat'iy", "ru": "Строго"},
                "description": {"uz": "Faqat to'liq va to'g'ri javob hisoblanadi", "ru": "Засчитываю только полный верный ответ"},
            },
        ],
    },
    {
        "id": "feedback_language",
        "type": "single",
        "required": True,
        "icon": "chat",
        "title": {"uz": "AI o'quvchilarga qaysi tilda izoh yozsin?", "ru": "На каком языке ИИ пишет ученикам?"},
        "options": [
            {"id": "uz", "label": {"uz": "O'zbekcha", "ru": "Узбекский"}},
            {"id": "ru", "label": {"uz": "Ruscha", "ru": "Русский"}},
            {"id": "en", "label": {"uz": "Inglizcha", "ru": "Английский"}},
        ],
    },
    {
        "id": "notes",
        "type": "text",
        "required": False,
        "icon": "edit",
        "max_length": 500,
        "title": {"uz": "AI yana nimani bilishi kerak?", "ru": "Что ещё должен знать ИИ?"},
        "hint": {
            "uz": "Masalan: \"Yechim yo'lini yozmasa, ball kamaytirilsin\"",
            "ru": "Например: «Без записи решения снижать балл»",
        },
    },
]

_BY_ID = {q["id"]: q for q in QUESTIONS}


def localized_questions(lang: str) -> list[dict[str, Any]]:
    lang = lang if lang in ("uz", "ru") else "uz"

    def pick(value: Any) -> Any:
        if isinstance(value, dict) and "uz" in value:
            return value.get(lang) or value["uz"]
        if isinstance(value, dict):
            return {k: pick(v) for k, v in value.items()}
        if isinstance(value, list):
            return [pick(v) for v in value]
        return value

    return [pick(q) for q in QUESTIONS]


def validate_answers(answers: dict[str, Any]) -> dict[str, Any]:
    clean: dict[str, Any] = {}
    errors: dict[str, str] = {}
    unknown = set(answers) - set(_BY_ID)
    for key in unknown:
        errors[key] = "Noma'lum savol"

    for q in QUESTIONS:
        qid = q["id"]
        value = answers.get(qid)
        empty = value is None or value == "" or value == []
        if empty:
            if q["required"]:
                errors[qid] = "Javob berilishi shart"
            continue

        option_ids = {o["id"] for o in q.get("options", [])}
        if q["type"] == "single":
            if not isinstance(value, str) or value not in option_ids:
                errors[qid] = "Noto'g'ri variant"
                continue
            clean[qid] = value
        elif q["type"] == "multi":
            if not isinstance(value, list) or not all(isinstance(v, str) and v in option_ids for v in value):
                errors[qid] = "Noto'g'ri variant"
                continue
            # Tartibni savoldagidek saqlaymiz, takrorlarni olib tashlaymiz
            clean[qid] = [o["id"] for o in q["options"] if o["id"] in value]
        elif q["type"] == "text":
            if not isinstance(value, str):
                errors[qid] = "Matn bo'lishi kerak"
                continue
            text = " ".join(value.split())
            if len(text) > q["max_length"]:
                errors[qid] = f"{q['max_length']} belgidan oshmasin"
                continue
            if text:
                clean[qid] = text

    if errors:
        raise AppError("ONBOARDING_INVALID", "Javoblarni tekshiring", 422, {"fields": errors})
    return clean


def _label(qid: str, option_id: str) -> str:
    for o in _BY_ID[qid].get("options", []):
        if o["id"] == option_id:
            return o["label"]["uz"]
    return option_id


_STYLE_RULES = {
    "lenient": "yechim yo'li to'g'ri bo'lsa, arifmetik va kichik xatolar uchun ball deyarli kamaytirilmaydi",
    "balanced": "qisman to'g'ri yechimga qisman ball beriladi, xato qayerdaligi aniq ko'rsatiladi",
    "strict": "faqat to'liq va to'g'ri javob hisoblanadi, chala yechimga ball berilmaydi",
}


def build_ai_context(full_name: str, answers: dict[str, Any]) -> str:
    """Tekshiruvchi AI uchun o'qituvchi haqida qisqa, barqaror kontekst."""
    lines = [f"O'qituvchi: {full_name}."]
    if subjects := answers.get("subjects"):
        lines.append("Fanlar: " + ", ".join(_label("subjects", s) for s in subjects) + ".")
    if levels := answers.get("student_levels"):
        lines.append("O'quvchilar: " + ", ".join(_label("student_levels", s) for s in levels) + ".")
    if place := answers.get("teaching_place"):
        lines.append(f"Dars joyi: {_label('teaching_place', place)}.")
    if scale := answers.get("grading_scale"):
        lines.append(f"Baholash tizimi: {_label('grading_scale', scale)}.")
    if style := answers.get("checking_style"):
        lines.append(f"Tekshiruv uslubi: {_label('checking_style', style)} — {_STYLE_RULES[style]}.")
    if lang := answers.get("feedback_language"):
        lines.append(f"O'quvchiga izoh tili: {_label('feedback_language', lang)}.")
    if notes := answers.get("notes"):
        # O'qituvchining erkin matni alohida belgilanadi, prompt ichida chegaralangan holda beriladi
        lines.append(f"O'qituvchining qo'shimcha ko'rsatmasi: <<<{notes}>>>")
    return "\n".join(lines)
