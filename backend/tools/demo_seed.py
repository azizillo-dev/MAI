"""Taqdimot va skrinshotlar uchun realistik demo baza (faqat lokal, nomida "demo" bo'lgan SQLite fayl).

    DATABASE_URL=sqlite+aiosqlite:///D:/mentor_AI/backend/demo.db MEDIA_ROOT=demo_media \
        python -m tools.demo_seed

Kirish: o'qituvchi demo.ustoz@mentorai.uz, o'quvchi demo.oquvchi@mentorai.uz (kod dev rejimda ekranda chiqadi).
"""

import asyncio
import io
import random
import secrets
import sys
import uuid
from datetime import UTC, date, datetime, timedelta

from PIL import Image as PILImage, ImageDraw, ImageFont

from app.core.config import get_settings
from app.db.session import get_engine, get_sessionmaker
from app.models import (
    Assignment,
    Base,
    BadgeAward,
    Group,
    GroupMember,
    JetonLedger,
    StudentProfile,
    Submission,
    SubmissionFile,
    Subscription,
    TeacherProfile,
    User,
    XpEvent,
)
from app.services.assignments import to_scale
from app.services.gamification import evaluate_badges
from app.services.jetons import seed_jetons
from app.services.onboarding import build_ai_context
from app.services.plans import get_plan, seed_plans
from app.services.storage import get_storage

random.seed(7)
NOW = datetime.now(UTC)

MATH_STUDENTS = ["Jasur Aliyev", "Madina Yusupova", "Sardor Rahimov", "Nodira Ergasheva", "Bekzod Toshmatov",
                 "Malika Qodirova", "Otabek Nazarov", "Zarina Karimova", "Javohir Umarov", "Shahzoda Tursunova",
                 "Diyor Hasanov", "Sevara Mirzayeva", "Asadbek Sobirov", "Kamola Rashidova"]
ENG_STUDENTS = ["Azizbek Yo'ldoshev", "Mohira Abdullayeva", "Temur Ismoilov", "Dilfuza Normatova", "Ulug'bek Saidov",
                "Gulnoza Xolmatova", "Shoxrux Qosimov", "Lola Ahmedova", "Islom Jo'rayev", "Nigora Salimova"]

MATH_TASKS = [
    ("Natural sonlar ustida amallar", [r"Hisoblang: $125 \cdot 8 - 36 : 4$", r"Hisoblang: $(48 + 52) \cdot 7$",
                                        r"Hisoblang: $1000 - 17 \cdot 23$", r"Hisoblang: $2^5 + 3^3$"]),
    ("Kasrlarni qo'shish", [r"Hisoblang: $\frac{3}{4} + \frac{5}{6}$", r"Hisoblang: $\frac{2}{3} + \frac{1}{9}$",
                             r"Hisoblang: $1\frac{1}{2} + 2\frac{3}{4}$", r"Hisoblang: $\frac{7}{12} + \frac{5}{8}$",
                             r"Hisoblang: $\frac{3}{10} + \frac{4}{15}$"]),
    ("Kasrlarni ayirish", [r"Hisoblang: $\frac{5}{6} - \frac{1}{4}$", r"Hisoblang: $3\frac{1}{3} - 1\frac{5}{6}$",
                            r"Hisoblang: $\frac{11}{12} - \frac{3}{8}$", r"Hisoblang: $2 - \frac{7}{9}$"]),
    ("O'nli kasrlar", [r"Hisoblang: $3{,}75 + 12{,}8$", r"Hisoblang: $7{,}2 \cdot 0{,}5$", r"Hisoblang: $9{,}6 : 1{,}2$",
                       r"Hisoblang: $15 - 4{,}37$"]),
    ("Foizlar", [r"$240$ ning $15\%$ ini toping", r"$36$ soni qaysi sonning $12\%$ i?",
                 r"Narx $80\,000$ so'mdan $20\%$ ga kamaydi. Yangi narx?", r"$45$ ning $60$ ga nisbati necha foiz?"]),
    ("Proporsiya", [r"Proporsiyadan $x$ ni toping: $\frac{x}{12} = \frac{5}{4}$",
                    r"$\frac{3}{x} = \frac{9}{15}$ bo'lsa, $x = ?$", r"4 kg olma $36\,000$ so'm. 7 kg qancha?"]),
    ("Manfiy sonlar", [r"Hisoblang: $-15 + 28$", r"Hisoblang: $(-6) \cdot (-7) - 50$", r"Hisoblang: $-48 : 6 + 12$",
                       r"Hisoblang: $|{-9}| - |4 - 11|$"]),
    ("Chiziqli tenglamalar", [r"Tenglamani yeching: $3x + 7 = 22$", r"Tenglamani yeching: $5(x - 2) = 3x + 4$",
                               r"Tenglamani yeching: $\frac{x}{3} + 2 = 6$", r"Tenglamani yeching: $7 - 2x = x - 8$"]),
    ("Ifodalarni soddalashtirish", [r"Soddalashtiring: $3a + 5b - a + 2b$", r"Soddalashtiring: $4(2x - 3) - 5x$",
                                     r"Soddalashtiring: $(a + 3)^2 - a^2$"]),
    ("Darajalar", [r"Hisoblang: $2^3 \cdot 2^4$", r"Hisoblang: $\frac{5^7}{5^5}$", r"Hisoblang: $(3^2)^3 : 3^4$"]),
    ("Geometriya: perimetr va yuza", [r"Tomonlari $7$ va $12$ sm bo'lgan to'g'ri to'rtburchak yuzini toping",
                                       r"Kvadrat perimetri $36$ sm. Yuzi?", r"Uchburchak asosi $10$, balandligi $6$. Yuzi?"]),
]
ENG_TASKS = [
    ("Present Simple", ["She ___ (go) to school every day.", "They ___ (not/like) coffee.", "___ he ___ (play) football?"]),
    ("Past Simple", ["Yesterday I ___ (visit) my grandma.", "We ___ (see) a great film last night.",
                     "She ___ (not/come) to the party."]),
    ("Vocabulary: Family", ["Translate: amaki", "Translate: nevara", "Translate: qaynona", "Use 'cousin' in a sentence."]),
    ("Present Continuous", ["Look! It ___ (rain).", "I ___ (read) a book now.", "What ___ you ___ (do)?"]),
    ("Articles a/an/the", ["I saw ___ elephant at ___ zoo.", "She is ___ best student in ___ class.",
                           "Can you pass me ___ salt?"]),
    ("Comparatives", ["Tashkent is ___ (big) than Samarkand.", "This task is ___ (difficult) than that one.",
                      "My brother is ___ (tall) in our family."]),
    ("Future: will / going to", ["Look at the clouds! It ___ rain.", "I think she ___ pass the exam.",
                                 "We ___ visit Bukhara next week (plan)."]),
    ("Reading: My Hobby", ["Answer: What is the author's hobby?", "Answer: How often does he practise?",
                           "Find 3 adjectives in the text."]),
    ("Prepositions of time", ["I was born ___ 2012.", "The lesson starts ___ 9 o'clock.", "We meet ___ Monday."]),
    ("Irregular verbs", ["Write V2 and V3: go", "Write V2 and V3: write", "Write V2 and V3: bring", "Write V2 and V3: teach"]),
]
MATH_COMMENTS = ["Umumiy maxrajni noto'g'ri topgan", "Ishorani unutgan", "Hisobda xato: ko'paytirishda adashgan",
                 "Javob qisqartirilmagan", "Aralash kasrni noto'g'ri kasrga o'tkazishda xato",
                 "Qavsni ochishda ishora almashmagan", "Yechim yo'li yozilmagan"]
ENG_COMMENTS = ["Fe'lning 3-shaxs qo'shimchasi (-s) tushib qolgan", "Noto'g'ri fe'l shakli: went o'rniga goed",
                "Artikl noto'g'ri", "Imloda xato", "Zamon noto'g'ri tanlangan"]
FEEDBACK = [
    "Zo'r ish! Deyarli hammasi to'g'ri. Kasrlarni qisqartirishni unutmang.",
    "Yaxshi! Faqat bitta misolda ishorani unutgansiz — javobni tekshirib chiqing.",
    "Katta o'sish ko'ryapman! Umumiy maxrajni topishni yana bir mashq qiling.",
    "Barakalla, ish toza va tartibli. Shunday davom eting!",
    "Ba'zi misollarda hisob xatosi bor. Har bir qadamni alohida yozsangiz, xato kamayadi.",
]


def _tex_answer(i: int) -> str:
    return f"${random.randint(2, 40)}$" if i % 2 else rf"$\frac{{{random.randint(1, 9)}}}{{{random.randint(10, 24)}}}$"


def _notebook_photo(lines: list[str]) -> bytes:
    """O'quvchi daftarining rasmi (skrinshot uchun): chiziqli qog'oz va yechimlar."""
    img = PILImage.new("RGB", (1200, 1600), (252, 250, 243))
    d = ImageDraw.Draw(img)
    for y in range(120, 1600, 62):
        d.line([(0, y), (1200, y)], fill=(205, 222, 240), width=2)
    d.line([(120, 0), (120, 1600)], fill=(240, 170, 170), width=3)
    try:
        font = ImageFont.truetype("segoepr.ttf", 46)
    except OSError:
        try:
            font = ImageFont.truetype("arial.ttf", 44)
        except OSError:
            font = ImageFont.load_default()
    for i, line in enumerate(lines):
        d.text((150, 135 + i * 124), line, fill=(28, 44, 120), font=font)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return buf.getvalue()


async def main() -> None:
    url = get_settings().database_url
    if "demo" not in url:
        sys.exit("Xavfsizlik: DATABASE_URL demo bazaga qaratilmagan (nomida 'demo' bo'lishi kerak)")
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    sm = get_sessionmaker()
    async with sm() as db:
        await seed_plans(db)
        await seed_jetons(db)
        pro = await get_plan(db, "pro")

        answers = {"subjects": ["math", "english"], "student_levels": ["grade_5_9"], "teaching_place": "learning_center",
                   "grading_scale": "5", "checking_style": "balanced", "feedback_language": "uz"}
        teacher = User(email="demo.ustoz@mentorai.uz", role="teacher", first_name="Dilnoza", last_name="Karimova",
                       locale="uz", is_active=True)
        db.add(teacher)
        await db.flush()
        db.add(TeacherProfile(user_id=teacher.id, onboarding_answers=answers, onboarding_completed_at=NOW - timedelta(days=70),
                              ai_context=build_ai_context(teacher.full_name, answers), default_grading_scale="5"))
        db.add(Subscription(teacher_id=teacher.id, plan_id=pro.id, status="active",
                            current_period_end=NOW + timedelta(days=24)))

        groups_spec = [("7-B matematika", "math", "5", MATH_STUDENTS, MATH_TASKS, MATH_COMMENTS),
                       ("9-A Ingliz tili", "english", "10", ENG_STUDENTS, ENG_TASKS, ENG_COMMENTS)]
        student_ids: list[uuid.UUID] = []
        jasur_last_sub = None
        for gname, subject, scale, names, tasks, comments in groups_spec:
            g = Group(teacher_id=teacher.id, name=gname, subject=subject, grading_scale=scale,
                      join_code=secrets.token_hex(4).upper(), join_password=secrets.token_hex(4).upper()[:8],
                      invite_token=secrets.token_hex(16), join_enabled=True, status="active")
            db.add(g)
            await db.flush()
            students = []
            for i, full in enumerate(names):
                first, last = full.split(" ", 1)
                email = "demo.oquvchi@mentorai.uz" if full == "Jasur Aliyev" else f"demo.{subject}{i}@mentorai.uz"
                u = User(email=email, role="student", first_name=first, last_name=last, locale="uz", is_active=True)
                db.add(u)
                await db.flush()
                db.add(StudentProfile(user_id=u.id, birth_date=date(2012, 1, 1) + timedelta(days=random.randint(0, 900)),
                                      is_locked=True))
                db.add(GroupMember(group_id=g.id, student_id=u.id, status="active", decided_at=NOW - timedelta(days=65)))
                # Har bir o'quvchining "qobiliyati" va haftalik o'sishi — grafiklar tabiiy chiqishi uchun
                ability = 92 if full == "Jasur Aliyev" else random.choice([55, 62, 70, 76, 82, 88, 94, 45])
                slope = 1.8 if full == "Jasur Aliyev" else random.choice([-2.5, -1, 0, 0.5, 1.5, 2.5, 3.5])
                students.append((u, ability, slope))
                student_ids.append(u.id)

            n_past = len(tasks) - 2
            for k, (title, texts) in enumerate(tasks):
                past = k < n_past
                weeks_ago = (n_past - k) * 7 / (n_past / 8) / 7 if past else 0
                due = NOW - timedelta(days=(n_past - k) * 5 - 1) if past else NOW + timedelta(days=k - n_past + 1, hours=6)
                items = [{"number": str(i + 1), "text": t, "answer": _tex_answer(i) if subject == "math" else None}
                         for i, t in enumerate(texts)]
                a = Assignment(group_id=g.id, teacher_id=teacher.id, title=title, source_type="text" if subject == "english" else "ai",
                               ai_params={"topic": title, "count": len(items), "difficulty": "medium"} if subject == "math" else None,
                               items=items, rubric=[], status="published", due_at=due, allow_late=True,
                               late_penalty_percent=10, published_at=due - timedelta(days=4),
                               instructions=None if subject == "math" else "Answer all questions in your notebook.")
                db.add(a)
                await db.flush()
                for u, ability, slope in students:
                    if not past and random.random() < 0.55:
                        continue  # ochiq vazifani hali topshirmaganlar
                    if past and random.random() < 0.08:
                        continue  # vaqtida topshirmaganlar
                    week_index = k / max(1, n_past - 1) * 8
                    pct = max(15.0, min(100.0, ability + slope * (week_index - 4) + random.gauss(0, 6)))
                    late = random.random() < 0.1
                    at = due - timedelta(hours=random.randint(2, 70)) if not late else due + timedelta(hours=random.randint(1, 20))
                    ai_items = []
                    for it in items:
                        ok = random.random() < pct / 100
                        ai_items.append({"number": it["number"], "verdict": "correct" if ok else random.choice(["incorrect", "partial"]),
                                         "comment": "" if ok else random.choice(comments)})
                    final = to_scale(pct, scale)
                    status = "graded"
                    if past and k == n_past - 1 and u is students[3][0]:
                        status, final = "needs_review", None  # ustoz ko'rishi kerak bo'lgan ish
                    s = Submission(assignment_id=a.id, student_id=u.id, submitted_at=at, is_late=late, attempt=1,
                                   status=status, ai_items=ai_items, ai_score_percent=round(pct, 1),
                                   ai_confidence=0.93 if status == "graded" else 0.52, ai_matches_assignment=True,
                                   feedback_student=random.choice(FEEDBACK),
                                   note_teacher="Hisoblashda shoshilyapti, yechim yo'lini yozdirishga e'tibor bering."
                                   if status == "graded" else "Rasm biroz xira, 3-misolni qo'lda tekshiring.",
                                   graded_at=at + timedelta(minutes=1), final_score=final)
                    db.add(s)
                    await db.flush()
                    if status == "graded":
                        pts = 10 + round(pct * 0.4) + (0 if late else 10)
                        db.add(XpEvent(student_id=u.id, group_id=g.id, submission_id=s.id, points=pts, created_at=at))
                    if u.first_name == "Jasur" and subject == "math":
                        jasur_last_sub = s

            # Qoralama: AI yaratgan, ustoz ko'rib chiqishi kerak
            if subject == "math":
                draft_items = [{"number": str(i + 1), "text": t, "answer": ans} for i, (t, ans) in enumerate([
                    (r"Hisoblang: $\frac{3}{4} + \frac{5}{6} - \frac{7}{12}$", "$1$"),
                    (r"Qiymatni toping: $3\frac{1}{2} - 1\frac{3}{5} + \frac{1}{10}$", "$2$"),
                    (r"Ifodaning qiymatini hisoblang: $\left(2\frac{1}{3} + 1\frac{1}{6}\right) - \frac{3}{4}$", r"$2\frac{3}{4}$"),
                    (r"Amallarni bajaring: $\frac{5}{12} + \left(2\frac{1}{4} - 1\frac{5}{6}\right)$", r"$\frac{5}{6}$"),
                    (r"Ifodaning qiymatini toping: $5 - \left(1\frac{3}{8} + 2\frac{1}{4}\right) + \frac{1}{2}$", r"$1\frac{7}{8}$"),
                ])]
                db.add(Assignment(group_id=g.id, teacher_id=teacher.id, title="Kasrlar bilan amallar", source_type="ai",
                                  ai_params={"topic": "Kasrlar bilan amallar", "count": 5, "difficulty": "medium"},
                                  items=draft_items, rubric=[], status="review", due_at=NOW + timedelta(days=3),
                                  allow_late=True, late_penalty_percent=0))
        await db.flush()

        # O'quvchi yuborgan daftar rasmi (tekshiruv sahifasi skrinshoti uchun)
        if jasur_last_sub is not None:
            data = _notebook_photo(["1)  15 : 3 = 5", "2)  5 · 12 = 60", "3)  60 : 4 = 15", "4)  x = 15 + 7 = 22",
                                    "Javob: 22 ta"])
            key = await get_storage().asave(f"submissions/{jasur_last_sub.assignment_id}", data, ".jpg")
            db.add(SubmissionFile(submission_id=jasur_last_sub.id, file_key=key, mime="image/jpeg", position=0,
                                  sha256=secrets.token_hex(32)))

        # Jetonlar: xarid va sovg'alar
        db.add(JetonLedger(teacher_id=teacher.id, jeton_code="sinf_yulduzi", delta=20, kind="purchase", created_at=NOW - timedelta(days=20)))
        db.add(JetonLedger(teacher_id=teacher.id, jeton_code="oltin_qalam", delta=10, kind="purchase", created_at=NOW - timedelta(days=20)))
        db.add(JetonLedger(teacher_id=teacher.id, jeton_code="aql_chirogi", delta=5, kind="purchase", created_at=NOW - timedelta(days=20)))
        gifts = [(student_ids[0], "sinf_yulduzi", "Sinf yulduzi", "star", "gold", "Barakalla, Jasur! Oyning eng yaxshi natijasi!"),
                 (student_ids[1], "oltin_qalam", "Oltin qalam", "pen", "gold", "Daftaring juda toza va chiroyli!"),
                 (student_ids[0], "aql_chirogi", "Aql chirog'i", "lightbulb", "purple", "Tenglamani o'zgacha usulda yechding — zo'r!")]
        for i, (sid, code, name, icon, tier, note) in enumerate(gifts):
            award = BadgeAward(student_id=sid, badge_code=code, source="gift", given_by=teacher.id,
                               awarded_at=NOW - timedelta(days=2 + i * 3),
                               meta={"name": name, "icon": icon, "tier": tier, "teacher": teacher.full_name, "note": note})
            db.add(award)
            await db.flush()
            db.add(JetonLedger(teacher_id=teacher.id, jeton_code=code, delta=-1, kind="gift", ref_id=award.id,
                               created_at=award.awarded_at))
        await db.commit()

        for sid in student_ids:
            await evaluate_badges(db, sid)
        await db.commit()
    print(f"Demo baza tayyor: {len(student_ids)} o'quvchi. O'qituvchi: demo.ustoz@mentorai.uz, "
          f"o'quvchi: demo.oquvchi@mentorai.uz")


if __name__ == "__main__":
    asyncio.run(main())
