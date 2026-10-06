"""Taqdimot uchun mavjud o'qituvchi akkauntiga universitet guruhini (talabalar, vazifalar, 8 haftalik natijalar) qo'shadi.

    python -m tools.showcase_seed --email ustoz@gmail.com [--photo daftar.jpg] [--review-photo xira.jpg]
    python -m tools.showcase_seed --email ustoz@gmail.com --remove      # demo ma'lumotlarni butunlay o'chirish

- O'qituvchining boshqa guruhlari va ma'lumotlariga tegilmaydi.
- Demo talabalar `@demo.mentorai.uz` emaili bilan yaratiladi: saytdagi ochiq statistikaga kirmaydi.
- Qayta ishga tushirilsa, eski demo guruh o'chirilib, yangidan yaratiladi.
- AI chaqiruvlari (ai_runs) yaratilmaydi: xarajat statistikasi soxtalashmaydi.
"""

import argparse
import asyncio
import random
import secrets
import uuid
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

from sqlalchemy import delete, func, select

from app.db.session import get_sessionmaker
from app.models import (
    Assignment,
    BadgeAward,
    Group,
    GroupMember,
    JetonLedger,
    StudentProfile,
    Submission,
    SubmissionFile,
    User,
    XpEvent,
)
from app.services.assignments import to_scale
from app.services.gamification import evaluate_badges, invalidate_stats
from app.services.onboarding import build_ai_context
from app.services.site import DEMO_EMAIL_DOMAIN
from app.services.storage import get_storage

GROUP_NAME = "007 Diskret Tuzilmalari"
NOW = datetime.now(UTC)

STUDENTS = [
    "Jasur Aliyev", "Madina Yusupova", "Sardor Rahimov", "Nodira Ergasheva", "Bekzod Toshmatov", "Malika Qodirova",
    "Otabek Nazarov", "Zarina Karimova", "Javohir Umarov", "Shahzoda Tursunova", "Diyor Hasanov", "Sevara Mirzayeva",
    "Asadbek Sobirov", "Kamola Rashidova", "Azizbek Yo'ldoshev", "Mohira Abdullayeva", "Temur Ismoilov",
    "Dilfuza Normatova", "Ulug'bek Saidov", "Gulnoza Xolmatova", "Shoxrux Qosimov", "Lola Ahmedova",
    "Islom Jo'rayev", "Nigora Salimova",
]

# (mavzu, [(shart, javob), ...]) — oxirgi ikkitasi hali ochiq vazifalar
TASKS = [
    ("To'plamlar va ular ustida amallar", [
        (r"$A=\{1,2,3,4\}$, $B=\{3,4,5\}$ bo'lsa, $A\cup B$ ni toping", r"$\{1,2,3,4,5\}$"),
        (r"$A\cap B$ ni toping", r"$\{3,4\}$"),
        (r"$A\setminus B$ ni toping", r"$\{1,2\}$"),
        (r"$|\mathcal{P}(A)|$ ni toping", r"$16$"),
    ]),
    ("Mulohazalar mantig'i: chinlik jadvallari", [
        (r"$p \to q$ formulaning chinlik jadvalini tuzing", r"$1,1,0,1$ ($pq$: 00, 01, 10, 11)"),
        (r"$(p \land q) \lor \lnot p$ formulaning chinlik jadvalini tuzing", r"$1,1,0,1$"),
        (r"$p \lor \lnot p$ tavtologiyami?", "Ha, tavtologiya"),
        (r"$p \land \lnot p$ formulaning turini aniqlang", "Aynan yolg'on (ziddiyat)"),
    ]),
    ("Mantiqiy ekvivalentlik va normal formalar", [
        (r"$\lnot(p \land q)$ ni de Morgan qonuni bilan yozing", r"$\lnot p \lor \lnot q$"),
        (r"$p \to q$ ni diz'yunksiya orqali ifodalang", r"$\lnot p \lor q$"),
        (r"$(p \lor q) \land (p \lor \lnot q)$ ni soddalashtiring", r"$p$"),
        (r"$p \oplus q$ uchun MDNF yozing", r"$(p \land \lnot q) \lor (\lnot p \land q)$"),
    ]),
    ("Predikatlar va kvantorlar", [
        (r"$\forall x \in \mathbb{N}:\ x^2 \ge x$ rostmi?", "Rost"),
        (r"$\exists x \in \mathbb{Z}:\ x^2 = 2$ rostmi?", "Yolg'on"),
        (r"$\lnot \forall x\, P(x)$ ni kvantor bilan yozing", r"$\exists x\, \lnot P(x)$"),
        (r"$\mathbb{Z}$ da $\forall x\, \exists y:\ x + y = 0$ rostmi?", "Rost"),
    ]),
    ("Matematik induksiya", [
        (r"$1+2+\dots+n = \frac{n(n+1)}{2}$ ni isbotlang", "Baza $n=1$, induksion o'tish $n \\to n+1$"),
        (r"$1+3+5+\dots+(2n-1) = n^2$ ni isbotlang", "Baza va induksion o'tish"),
        (r"$2^n > n$ ekanini barcha $n \ge 1$ uchun isbotlang", "Baza va induksion o'tish"),
        (r"$n^3 - n$ ning $6$ ga bo'linishini isbotlang", r"$n^3-n=(n-1)n(n+1)$"),
    ]),
    ("Munosabatlar va ularning xossalari", [
        (r"$A=\{1,2,3\}$, $R=\{(1,1),(2,2),(3,3),(1,2),(2,1)\}$. $R$ refleksivmi?", "Ha"),
        (r"$R$ simmetrikmi?", "Ha"),
        (r"$R$ tranzitivmi?", "Ha"),
        (r"$R$ ekvivalentlik munosabatimi? Sinflarini yozing", r"Ha: $\{1,2\},\ \{3\}$"),
    ]),
    ("Funksiyalar: in'ektiv, syur'ektiv, biektiv", [
        (r"$f:\mathbb{R}\to\mathbb{R}$, $f(x)=2x+3$ biektivmi?", "Ha"),
        (r"$f:\mathbb{R}\to\mathbb{R}$, $f(x)=x^2$ in'ektivmi?", "Yo'q"),
        (r"$f(x)=2x+3$ ning teskari funksiyasini toping", r"$f^{-1}(x)=\frac{x-3}{2}$"),
        (r"$f(x)=x+1$, $g(x)=2x$ bo'lsa, $(f\circ g)(3)$ ni toping", r"$7$"),
    ]),
    ("Kombinatorika: o'rinlashtirish va guruhlash", [
        (r"$P_5$ ni hisoblang", r"$120$"),
        (r"$A_6^2$ ni hisoblang", r"$30$"),
        (r"$C_8^3$ ni hisoblang", r"$56$"),
        (r"10 talabadan 3 kishilik guruhni necha usulda tuzish mumkin?", r"$C_{10}^3 = 120$"),
    ]),
    ("Nyuton binomi va Paskal uchburchagi", [
        (r"$(a+b)^4$ yoyilmasini yozing", r"$a^4+4a^3b+6a^2b^2+4ab^3+b^4$"),
        (r"$(x+2)^5$ yoyilmasida $x^3$ oldidagi koeffitsiyentni toping", r"$C_5^2 \cdot 2^2 = 40$"),
        (r"$\sum_{k=0}^{6} C_6^k$ ni hisoblang", r"$64$"),
        (r"Paskal uchburchagining 5-qatorini yozing", r"$1,5,10,10,5,1$"),
    ]),
    ("Rekurrent munosabatlar", [
        (r"$a_n = a_{n-1} + 3$, $a_1 = 2$. $a_{10}$ ni toping", r"$29$"),
        (r"$a_n = 2a_{n-1}$, $a_0 = 3$. $a_5$ ni toping", r"$96$"),
        (r"$F_1=F_2=1$ bo'lsa, $F_{10}$ ni toping", r"$55$"),
        (r"$a_n = 5a_{n-1} - 6a_{n-2}$ ning umumiy yechimini toping", r"$a_n = c_1 2^n + c_2 3^n$"),
    ]),
    ("Graflar: asosiy tushunchalar", [
        (r"$K_5$ to'liq grafda nechta qirra bor?", r"$10$"),
        (r"Uchlari darajalari $3,3,2,2,1,1$ bo'lgan grafda nechta qirra bor?", r"$6$"),
        (r"7 ta qirrali grafda uchlar darajalari yig'indisini toping", r"$14$"),
        (r"$K_{3,3}$ grafda nechta qirra bor?", r"$9$"),
    ]),
    ("Eyler va Gamilton graflari", [
        (r"$K_4$ grafida Eyler sikli bormi?", "Yo'q: barcha uchlar darajasi toq (3)"),
        (r"$K_5$ grafida Eyler sikli bormi?", "Ha: barcha uchlar darajasi juft (4)"),
        (r"Kyonigsberg ko'priklari masalasining yechimi bormi?", "Yo'q"),
        (r"$C_6$ sikl grafi Gamilton grafimi?", "Ha"),
    ]),
    ("Daraxtlar va o'zak daraxtlar", [
        (r"10 ta uchli daraxtda nechta qirra bor?", r"$9$"),
        (r"$K_4$ ning nechta o'zak daraxti bor?", r"$4^{4-2} = 16$"),
        (r"Balandligi 3 bo'lgan ikkilik daraxtda uchlar soni ko'pi bilan nechta?", r"$15$"),
        (r"Kruskal algoritmi qaysi masalani yechadi?", "Minimal o'zak daraxt"),
    ]),
]
N_OPEN = 2

DRAFT = ("Bul algebrasi", [
    (r"$x \lor x\bar{y}$ ni soddalashtiring", r"$x$"),
    (r"$\overline{x \lor y}$ ni de Morgan qonuni bilan yozing", r"$\bar{x}\,\bar{y}$"),
    (r"$f(x,y)=xy \lor x\bar{y}$ ni soddalashtiring", r"$x$"),
    (r"$x \oplus 1$ ni soddalashtiring", r"$\bar{x}$"),
    (r"$(x \lor y)(x \lor \bar{y})$ ni soddalashtiring", r"$x$"),
])

COMMENTS = [
    "Chinlik jadvalida bitta satr noto'g'ri", "De Morgan qonunida inkor to'g'ri kiritilmagan",
    "Induksion o'tish isbotlanmagan, faqat baza tekshirilgan", "Kombinatsiya va o'rinlashtirish adashtirilgan",
    "Tranzitivlik sharti tekshirilmagan", "Darajalar yig'indisi hisobida xato", "Javob asoslanmagan",
]
FEEDBACK = [
    "Yaxshi ish! Deyarli hammasi to'g'ri, faqat oxirgi misolda qavslarga e'tibor bering.",
    "Isbotning bazasi to'g'ri, lekin induksion o'tishni to'liq yozing.",
    "Kombinatorika masalalarida avval tartib muhimmi yoki yo'qmi — shuni aniqlang.",
    "Barakalla, yechimlar aniq va asoslangan. Shunday davom eting!",
    "Ba'zi javoblar to'g'ri, ammo asoslash yetishmaydi. Har bir qadamni yozing.",
]


async def remove(db, teacher: User) -> int:
    """Faqat demo guruh va demo talabalarni o'chiradi."""
    gids = list(await db.scalars(select(Group.id).where(Group.teacher_id == teacher.id, Group.name == GROUP_NAME)))
    sids = list(await db.scalars(select(User.id).where(User.email.like(f"%@{DEMO_EMAIL_DOMAIN}"))))
    if gids:
        aids = list(await db.scalars(select(Assignment.id).where(Assignment.group_id.in_(gids))))
        sub_ids = list(await db.scalars(select(Submission.id).where(Submission.assignment_id.in_(aids)))) if aids else []
        if sub_ids:
            await db.execute(delete(XpEvent).where(XpEvent.submission_id.in_(sub_ids)))
            await db.execute(delete(SubmissionFile).where(SubmissionFile.submission_id.in_(sub_ids)))
            await db.execute(delete(Submission).where(Submission.id.in_(sub_ids)))
        if aids:
            await db.execute(delete(Assignment).where(Assignment.id.in_(aids)))
        await db.execute(delete(XpEvent).where(XpEvent.group_id.in_(gids)))
        await db.execute(delete(GroupMember).where(GroupMember.group_id.in_(gids)))
        await db.execute(delete(Group).where(Group.id.in_(gids)))
    if sids:
        award_ids = list(await db.scalars(select(BadgeAward.id).where(BadgeAward.student_id.in_(sids))))
        if award_ids:
            await db.execute(delete(JetonLedger).where(JetonLedger.ref_id.in_(award_ids)))
        await db.execute(delete(BadgeAward).where(BadgeAward.student_id.in_(sids)))
        await db.execute(delete(XpEvent).where(XpEvent.student_id.in_(sids)))
        await db.execute(delete(GroupMember).where(GroupMember.student_id.in_(sids)))
        await db.execute(delete(StudentProfile).where(StudentProfile.user_id.in_(sids)))
        await db.execute(delete(User).where(User.id.in_(sids)))
    # Demo uchun berilgan jetonlar
    await db.execute(delete(JetonLedger).where(JetonLedger.teacher_id == teacher.id, JetonLedger.kind == "demo"))
    await db.commit()
    return len(sids)


async def seed(email: str, photo: Path | None, do_remove: bool, review_photo: Path | None = None) -> None:
    rnd = random.Random(2026)
    async with get_sessionmaker()() as db:
        teacher = await db.scalar(select(User).where(User.email == email.lower(), User.role == "teacher"))
        if teacher is None:
            raise SystemExit(f"O'qituvchi topilmadi: {email}")
        removed = await remove(db, teacher)
        if do_remove:
            invalidate_stats(teacher_id=teacher.id)
            print(f"O'chirildi: {removed} ta demo talaba va '{GROUP_NAME}' guruhi")
            return

        # O'qituvchi profili: universitet (mavjud javoblar saqlanadi, faqat qo'shiladi)
        prof = teacher.teacher
        if prof is not None and prof.onboarding_answers:
            answers = dict(prof.onboarding_answers)
            levels = list(answers.get("student_levels") or [])
            if "university" not in levels:
                answers["student_levels"] = [*levels, "university"]
            answers["teaching_place"] = "university"
            prof.onboarding_answers = answers
            prof.ai_context = build_ai_context(teacher.full_name, answers)

        g = Group(teacher_id=teacher.id, name=GROUP_NAME, subject="math", grading_scale="5",
                  join_code=secrets.token_hex(4).upper(), join_password=secrets.token_hex(4).upper()[:8],
                  invite_token=secrets.token_hex(16), join_enabled=True, status="active")
        db.add(g)
        await db.flush()

        students = []
        for i, full in enumerate(STUDENTS):
            first, last = full.split(" ", 1)
            u = User(email=f"talaba{i + 1:02d}@{DEMO_EMAIL_DOMAIN}", role="student", first_name=first, last_name=last,
                     locale="uz", is_active=True)
            db.add(u)
            await db.flush()
            db.add(StudentProfile(user_id=u.id, birth_date=date(2005, 1, 1) + timedelta(days=rnd.randint(0, 900)),
                                  is_locked=True))
            db.add(GroupMember(group_id=g.id, student_id=u.id, status="active", decided_at=NOW - timedelta(days=62)))
            # Har bir talabaning "darajasi" va haftalik o'sishi — grafiklar tabiiy chiqishi uchun
            ability = 93 if i == 0 else rnd.choice([48, 56, 63, 70, 76, 82, 88, 94])
            slope = 1.6 if i == 0 else rnd.choice([-2.5, -1, 0, 0.5, 1.5, 2.5, 3.5])
            students.append((u, ability, slope))

        n_past = len(TASKS) - N_OPEN
        review_sub = photo_sub = None
        for k, (title, pairs) in enumerate(TASKS):
            past = k < n_past
            due = NOW - timedelta(days=(n_past - k) * 5 - 1) if past else NOW + timedelta(days=k - n_past + 2, hours=6)
            items = [{"number": str(i + 1), "text": t, "answer": ans} for i, (t, ans) in enumerate(pairs)]
            a = Assignment(group_id=g.id, teacher_id=teacher.id, title=title, source_type="ai",
                           ai_params={"topic": title, "count": len(items), "difficulty": "medium"},
                           items=items, rubric=[], status="published", due_at=due, allow_late=True,
                           late_penalty_percent=10, published_at=due - timedelta(days=4))
            db.add(a)
            await db.flush()
            # Mavzu qiyinligi: induksiya va rekurrent munosabatlar talabalarga og'irroq
            hardness = {"Matematik induksiya": -14, "Rekurrent munosabatlar": -9,
                        "Mantiqiy ekvivalentlik va normal formalar": -6}.get(title, 0)
            for idx, (u, ability, slope) in enumerate(students):
                if not past and rnd.random() < 0.55:
                    continue  # ochiq vazifani hali topshirmaganlar
                if past and rnd.random() < 0.07:
                    continue  # topshirmaganlar
                week = k / max(1, n_past - 1) * 8
                pct = max(15.0, min(100.0, ability + hardness + slope * (week - 4) + rnd.gauss(0, 6)))
                late = rnd.random() < 0.1
                at = due - timedelta(hours=rnd.randint(2, 70)) if not late else due + timedelta(hours=rnd.randint(1, 20))
                ai_items = []
                for it in items:
                    ok = rnd.random() < pct / 100
                    ai_items.append({"number": it["number"], "verdict": "correct" if ok else rnd.choice(["incorrect", "partial"]),
                                     "comment": "" if ok else rnd.choice(COMMENTS)})
                status, final = "graded", to_scale(pct, "5")
                if past and k == n_past - 1 and idx in (3, 9):
                    status, final = "needs_review", None  # AI ishonchi past — ustoz ko'rishi kerak
                s = Submission(assignment_id=a.id, student_id=u.id, submitted_at=at, is_late=late, attempt=1,
                               status=status, ai_items=ai_items, ai_score_percent=round(pct, 1),
                               ai_confidence=0.94 if status == "graded" else 0.55, ai_matches_assignment=True,
                               feedback_student=rnd.choice(FEEDBACK),
                               note_teacher="Formal isbotlarda qadamlarni tushirib qoldiryapti, induksiyani takrorlash kerak."
                               if status == "graded" else "Rasm biroz xira, 3-misolni qo'lda tekshiring.",
                               graded_at=at + timedelta(minutes=1) if status == "graded" else None, final_score=final)
                db.add(s)
                await db.flush()
                if status == "graded":
                    pts = 10 + round(pct * 0.4) + (0 if late else 10)
                    db.add(XpEvent(student_id=u.id, group_id=g.id, submission_id=s.id, points=pts, created_at=at))
                if status == "needs_review" and review_sub is None:
                    review_sub = s
                if title.startswith("Kombinatorika") and idx == 0:
                    photo_sub = s

        # AI tayyorlagan qoralama — ustoz ko'rib chiqib e'lon qiladi
        title, pairs = DRAFT
        db.add(Assignment(group_id=g.id, teacher_id=teacher.id, title=title, source_type="ai",
                          ai_params={"topic": title, "count": len(pairs), "difficulty": "medium"},
                          items=[{"number": str(i + 1), "text": t, "answer": ans} for i, (t, ans) in enumerate(pairs)],
                          rubric=[], status="review", due_at=NOW + timedelta(days=4), allow_late=True,
                          late_penalty_percent=0))
        await db.flush()

        # Talaba daftarining rasmi (tekshiruv sahifasi uchun)
        for sub, path in ((photo_sub, photo), (review_sub, review_photo)):
            if sub is None or path is None or not path.exists():
                continue
            key = await get_storage().asave(f"submissions/{sub.assignment_id}", path.read_bytes(), ".jpg")
            db.add(SubmissionFile(submission_id=sub.id, file_key=key, mime="image/jpeg", position=0,
                                  sha256=secrets.token_hex(32)))

        # Ustoz sovg'alari (demo uchun berilgan jetonlar "demo" turida yoziladi — sotuvga kirmaydi)
        gifts = [(0, "sinf_yulduzi", "Sinf yulduzi", "star", "gold", "Barakalla, Jasur! Guruhdagi eng yaxshi natija!"),
                 (1, "oltin_qalam", "Oltin qalam", "pen", "gold", "Isbotlaring juda toza va tartibli!"),
                 (0, "aql_chirogi", "Aql chirog'i", "lightbulb", "purple", "Rekurrent tenglamani o'zgacha usulda yechding — zo'r!")]
        for code in {c for _, c, *_ in gifts}:
            db.add(JetonLedger(teacher_id=teacher.id, jeton_code=code, delta=3, kind="demo", created_at=NOW - timedelta(days=20)))
        for i, (idx, code, name, icon, tier, note) in enumerate(gifts):
            award = BadgeAward(student_id=students[idx][0].id, badge_code=code, source="gift", given_by=teacher.id,
                               awarded_at=NOW - timedelta(days=2 + i * 3),
                               meta={"name": name, "icon": icon, "tier": tier, "teacher": teacher.full_name, "note": note})
            db.add(award)
            await db.flush()
            db.add(JetonLedger(teacher_id=teacher.id, jeton_code=code, delta=-1, kind="demo", ref_id=award.id,
                               created_at=award.awarded_at))
        await db.commit()

        for u, *_ in students:
            await evaluate_badges(db, u.id)
        await db.commit()
        invalidate_stats(student_ids=[u.id for u, *_ in students], group_id=g.id, teacher_id=teacher.id)
        subs = await db.scalar(select(func.count()).select_from(Submission).join(Assignment)
                               .where(Assignment.group_id == g.id))
        print(f"Tayyor: '{GROUP_NAME}' — {len(students)} talaba, {len(TASKS)} vazifa (+1 qoralama), {subs} ta ish. "
              f"O'qituvchi: {teacher.full_name} <{teacher.email}>")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", required=True)
    ap.add_argument("--photo", type=Path, help="'Kombinatorika' ishiga daftar rasmi")
    ap.add_argument("--review-photo", type=Path, help="'Tekshirish kerak' ishiga daftar rasmi")
    ap.add_argument("--remove", action="store_true")
    a = ap.parse_args()
    asyncio.run(seed(a.email, a.photo, a.remove, a.review_photo))


if __name__ == "__main__":
    main()
