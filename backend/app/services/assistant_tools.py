"""AI yordamchi chaqiradigan "vositalar": aniq raqamlarni server bazadan hisoblaydi.

AI hech qachon o'zi hisoblamaydi — faqat shu funksiyalar qaytargan ma'lumotni tushuntiradi.
Har bir funksiya faqat SHU o'qituvchining guruhlari va o'quvchilari doirasida ishlaydi.
"""

import uuid
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import as_utc, utcnow
from app.models import (
    Assignment,
    AssignmentStatus,
    Group,
    GroupMember,
    GroupStatus,
    MemberStatus,
    Submission,
    SubmissionStatus,
    User,
    XpEvent,
)
from app.services.assignments import TASHKENT
from app.services.gamification import leaderboard, level_info


def _percent(s: Submission) -> float | None:
    if s.status != SubmissionStatus.GRADED or s.final_score is None:
        return None
    scale = float(s.assignment.group.grading_scale)
    return round(s.final_score / scale * 100, 1) if scale else None


def _norm(text: str) -> str:
    return text.lower().replace("ʻ", "'").replace("ʼ", "'").replace("‘", "'").replace("’", "'").replace("`", "'")


def _trend(percents: list[float]) -> dict[str, Any]:
    if len(percents) < 2:
        return {"direction": "ma'lumot kam", "first_half_avg": None, "second_half_avg": None}
    half = len(percents) // 2
    first = sum(percents[:half]) / half
    second = sum(percents[half:]) / (len(percents) - half)
    diff = second - first
    direction = "o'smoqda" if diff >= 5 else "pasaymoqda" if diff <= -5 else "barqaror"
    return {"direction": direction, "first_half_avg": round(first, 1), "second_half_avg": round(second, 1),
            "change_points": round(diff, 1)}


class AssistantTools:
    def __init__(self, db: AsyncSession, teacher: User) -> None:
        self.db = db
        self.teacher = teacher
        # Ilovada mini grafik chizish uchun tuzilgan kartalar
        self.attachments: list[dict[str, Any]] = []

    async def _groups(self) -> list[Group]:
        return list(await self.db.scalars(
            select(Group).where(Group.teacher_id == self.teacher.id, Group.status == GroupStatus.ACTIVE).order_by(Group.created_at)
        ))

    async def _student_in_my_groups(self, student_id: uuid.UUID) -> list[Group]:
        return list(await self.db.scalars(
            select(Group).join(GroupMember, GroupMember.group_id == Group.id).where(
                Group.teacher_id == self.teacher.id, Group.status == GroupStatus.ACTIVE,
                GroupMember.student_id == student_id, GroupMember.status == MemberStatus.ACTIVE,
            )
        ))

    async def roster(self) -> str:
        """Promptga qo'shiladigan ro'yxat: AI qidiruv bosqichisiz to'g'ri id bilan so'rashi uchun."""
        lines = []
        for g in await self._groups():
            lines.append(f"Group \"{g.name}\" ({g.subject}, {g.grading_scale}-point) group_id={g.id}")
            students = await self.db.scalars(
                select(User).join(GroupMember, GroupMember.student_id == User.id)
                .where(GroupMember.group_id == g.id, GroupMember.status == MemberStatus.ACTIVE)
                .order_by(User.last_name)
            )
            for u in students:
                lines.append(f"  - {u.full_name} student_id={u.id}")
        return "\n".join(lines) or "(no groups yet)"

    # ------------------------------------------------------------ vositalar

    async def list_groups(self) -> dict:
        out = []
        for g in await self._groups():
            students = await self.db.scalar(select(func.count()).select_from(GroupMember).where(
                GroupMember.group_id == g.id, GroupMember.status == MemberStatus.ACTIVE))
            out.append({"group_id": str(g.id), "name": g.name, "subject": g.subject,
                        "grading_scale": g.grading_scale, "students": students})
        return {"groups": out}

    async def find_students(self, query: str) -> dict:
        q = _norm(query.strip())
        rows = await self.db.execute(
            select(User, Group.name).join(GroupMember, GroupMember.student_id == User.id)
            .join(Group, Group.id == GroupMember.group_id)
            .where(Group.teacher_id == self.teacher.id, Group.status == GroupStatus.ACTIVE,
                   GroupMember.status == MemberStatus.ACTIVE)
        )
        matches = []
        for user, group_name in rows.all():
            full = _norm(f"{user.first_name} {user.last_name}")
            if all(part in full for part in q.split()):
                matches.append({"student_id": str(user.id), "name": user.full_name, "group": group_name})
        return {"matches": matches[:8], "count": len(matches)}

    async def student_report(self, student_id: str) -> dict:
        try:
            sid = uuid.UUID(student_id)
        except ValueError:
            return {"error": "Noto'g'ri student_id. Avval find_students bilan qidiring"}
        groups = await self._student_in_my_groups(sid)
        if not groups:
            return {"error": "Bu o'quvchi sizning guruhlaringizda emas"}
        student = await self.db.get(User, sid)
        group_ids = [g.id for g in groups]

        subs = list(await self.db.scalars(
            select(Submission).join(Assignment, Assignment.id == Submission.assignment_id)
            .where(Submission.student_id == sid, Assignment.group_id.in_(group_ids))
            .order_by(Submission.submitted_at)
        ))
        graded = [s for s in subs if _percent(s) is not None]
        percents = [_percent(s) for s in graded]
        submitted_ids = {s.assignment_id for s in subs}
        past_due = list(await self.db.scalars(
            select(Assignment).where(Assignment.group_id.in_(group_ids), Assignment.status == AssignmentStatus.PUBLISHED,
                                     Assignment.due_at < utcnow())
        ))
        missing = [a.title for a in past_due if a.id not in submitted_ids]
        open_now = list(await self.db.scalars(
            select(Assignment).where(Assignment.group_id.in_(group_ids), Assignment.status == AssignmentStatus.PUBLISHED,
                                     Assignment.due_at >= utcnow())
        ))
        open_pending = [a.title for a in open_now if a.id not in submitted_ids]

        mistakes = []
        for s in reversed(graded[-6:]):
            for item in s.ai_items or []:
                if item.get("verdict") in ("incorrect", "partial") and item.get("comment"):
                    mistakes.append(f"{s.assignment.title}, {item.get('number')}: {item['comment']}")
        xp = int(await self.db.scalar(select(func.coalesce(func.sum(XpEvent.points), 0)).where(XpEvent.student_id == sid)))
        board = await leaderboard(self.db, groups[0], "group", "all")
        rank = next((r["rank"] for r in board if r["student_id"] == sid), None)

        report = {
            "name": student.full_name,
            "groups": [g.name for g in groups],
            "graded_works": len(graded),
            "avg_percent": round(sum(percents) / len(percents), 1) if percents else None,
            "best_percent": max(percents) if percents else None,
            "worst_percent": min(percents) if percents else None,
            "trend": _trend(percents),
            "recent": [
                {"assignment": s.assignment.title,
                 "date": as_utc(s.submitted_at).astimezone(TASHKENT).strftime("%d.%m"),
                 "score": s.final_score, "scale": s.assignment.group.grading_scale,
                 "percent": _percent(s), "late": s.is_late}
                for s in graded[-6:]
            ],
            "late_count": sum(1 for s in subs if s.is_late),
            "missing_assignments": missing,
            "open_not_submitted_yet": open_pending,
            "waiting_review": sum(1 for s in subs if s.status in (SubmissionStatus.NEEDS_REVIEW, SubmissionStatus.FAILED)),
            "recent_mistakes": mistakes[:8],
            "xp": xp,
            "level": level_info(xp)["level_name"],
            "rank_in_group": rank,
            "group_size": len(board),
        }
        self.attachments.append({
            "type": "student", "student_id": str(sid), "name": student.full_name,
            "avg_percent": report["avg_percent"], "trend": report["trend"]["direction"],
            "points": [p for p in percents[-10:]], "missing": len(missing), "rank": rank, "group_size": len(board),
        })
        return report

    async def group_report(self, group_id: str) -> dict:
        groups = {str(g.id): g for g in await self._groups()}
        g = groups.get(group_id)
        if g is None:
            return {"error": "Guruh topilmadi. Avval list_groups chaqiring"}
        members = list(await self.db.scalars(
            select(User).join(GroupMember, GroupMember.student_id == User.id)
            .where(GroupMember.group_id == g.id, GroupMember.status == MemberStatus.ACTIVE)
        ))
        assignments = list(await self.db.scalars(
            select(Assignment).where(Assignment.group_id == g.id, Assignment.status == AssignmentStatus.PUBLISHED)
            .order_by(Assignment.due_at)
        ))
        subs = list(await self.db.scalars(
            select(Submission).where(Submission.assignment_id.in_([a.id for a in assignments]))
        )) if assignments else []

        per_student: dict[uuid.UUID, list[float]] = {m.id: [] for m in members}
        for s in subs:
            p = _percent(s)
            if p is not None and s.student_id in per_student:
                per_student[s.student_id].append(p)
        due_ids = {a.id for a in assignments if as_utc(a.due_at) < utcnow()}
        done = {(s.student_id, s.assignment_id) for s in subs}
        missing_count = {m.id: sum(1 for aid in due_ids if (m.id, aid) not in done) for m in members}
        open_ids = {a.id for a in assignments if as_utc(a.due_at) >= utcnow()}
        avgs = {m.id: sum(per_student[m.id]) / len(per_student[m.id]) for m in members if per_student[m.id]}
        names = {m.id: m.full_name for m in members}
        ranked = sorted(avgs.items(), key=lambda kv: -kv[1])

        # E'tibor kerak: past natija, muddati o'tgan topshirilmagan, ochiq vazifani hali topshirmagan, bahosi yo'q
        attention = []
        for m in members:
            reasons = []
            if m.id in avgs and avgs[m.id] < 71:
                reasons.append(f"o'rtacha {round(avgs[m.id])}%")
            if missing_count[m.id]:
                reasons.append(f"{missing_count[m.id]} ta vazifani muddatida topshirmagan")
            pending_open = sum(1 for aid in open_ids if (m.id, aid) not in done)
            if pending_open:
                reasons.append(f"{pending_open} ta ochiq vazifani hali topshirmagan")
            if m.id not in avgs and not any(sid == m.id for sid, _ in done):
                reasons.append("hali birorta ish topshirmagan")
            if reasons:
                severity = (100 - avgs.get(m.id, 50)) + missing_count[m.id] * 20 + pending_open * 5
                attention.append((severity, {"name": m.full_name, "avg_percent": round(avgs[m.id], 1) if m.id in avgs else None,
                                             "reasons": reasons}))
        attention.sort(key=lambda x: -x[0])
        all_p = [p for v in per_student.values() for p in v]
        expected = len(members) * len(due_ids)

        mistakes = []
        for s in subs[-30:]:
            for item in s.ai_items or []:
                if item.get("verdict") in ("incorrect", "partial") and item.get("comment"):
                    mistakes.append(item["comment"])

        report = {
            "name": g.name,
            "subject": g.subject,
            "students": len(members),
            "avg_percent": round(sum(all_p) / len(all_p), 1) if all_p else None,
            "submission_rate_percent": round(sum(1 for m in members for aid in due_ids if (m.id, aid) in done) / expected * 100)
            if expected else None,
            "top_students": [{"name": names[sid], "avg_percent": round(a, 1)} for sid, a in ranked[:3]],
            "needs_attention": [item for _, item in attention[:6]],
            "assignments": [
                {"title": a.title, "submitted": sum(1 for s in subs if s.assignment_id == a.id), "members": len(members),
                 "avg_percent": (lambda ps: round(sum(ps) / len(ps), 1) if ps else None)(
                     [p for s in subs if s.assignment_id == a.id and (p := _percent(s)) is not None])}
                for a in assignments[-6:]
            ],
            "common_mistakes_sample": mistakes[:10],
        }
        self.attachments.append({
            "type": "group", "group_id": str(g.id), "name": g.name, "avg_percent": report["avg_percent"],
            "students": len(members), "submission_rate": report["submission_rate_percent"],
        })
        return report


    async def _group_data(self, group_id: str, last_n: int | None = None):
        groups = {str(g.id): g for g in await self._groups()}
        g = groups.get(group_id)
        if g is None:
            return None, [], [], []
        members = list(await self.db.scalars(
            select(User).join(GroupMember, GroupMember.student_id == User.id)
            .where(GroupMember.group_id == g.id, GroupMember.status == MemberStatus.ACTIVE)
        ))
        assignments = list(await self.db.scalars(
            select(Assignment).where(Assignment.group_id == g.id, Assignment.status == AssignmentStatus.PUBLISHED,
                                     Assignment.due_at < utcnow())
            .order_by(Assignment.due_at)
        ))
        if last_n:
            assignments = assignments[-last_n:]
        subs = list(await self.db.scalars(
            select(Submission).where(Submission.assignment_id.in_([a.id for a in assignments]))
        )) if assignments else []
        return g, members, assignments, subs

    async def students_below(self, group_id: str, threshold: float = 70, last_n: int = 3) -> dict:
        last_n = max(1, min(int(last_n or 3), 20))
        threshold = max(1.0, min(float(threshold or 70), 100.0))
        g, members, assignments, subs = await self._group_data(group_id, last_n)
        if g is None:
            return {"error": "Guruh topilmadi. Avval list_groups chaqiring"}
        if not assignments:
            return {"group": g.name, "note": "Bu guruhda muddati o'tgan vazifa hali yo'q"}
        by = {(s.student_id, s.assignment_id): s for s in subs}
        below, missed = [], []
        for m in members:
            results = []
            for a in assignments:
                s = by.get((m.id, a.id))
                results.append({"assignment": a.title, "percent": round(p, 1) if s and (p := _percent(s)) is not None
                                else None, "submitted": s is not None})
            graded = [r["percent"] for r in results if r["percent"] is not None]
            not_submitted = [r["assignment"] for r in results if not r["submitted"]]
            if graded and sum(graded) / len(graded) < threshold:
                below.append({"name": m.full_name, "avg_percent": round(sum(graded) / len(graded), 1),
                              "results": results})
            if not_submitted:
                missed.append({"name": m.full_name, "not_submitted": not_submitted})
        below.sort(key=lambda x: x["avg_percent"])
        return {"group": g.name, "assignments_considered": [a.title for a in assignments],
                "threshold_percent": threshold, "below_threshold": below, "did_not_submit": missed,
                "students_total": len(members)}

    async def difficult_topics(self, group_id: str, last_n: int = 5) -> dict:
        last_n = max(1, min(int(last_n or 5), 20))
        g, members, assignments, subs = await self._group_data(group_id, last_n)
        if g is None:
            return {"error": "Guruh topilmadi. Avval list_groups chaqiring"}
        if not assignments:
            return {"group": g.name, "note": "Bu guruhda muddati o'tgan vazifa hali yo'q"}
        per_assignment = []
        item_stats: dict[tuple, dict] = {}
        for a in assignments:
            a_subs = [s for s in subs if s.assignment_id == a.id]
            ps = [p for s in a_subs if (p := _percent(s)) is not None]
            per_assignment.append({"title": a.title, "avg_percent": round(sum(ps) / len(ps), 1) if ps else None,
                                   "submitted": len(a_subs), "students": len(members)})
            texts = {str(i.get("number")): i.get("text") for i in (a.items or [])}
            for s in a_subs:
                for it in s.ai_items or []:
                    key = (a.title, str(it.get("number")))
                    st = item_stats.setdefault(key, {"assignment": a.title, "number": key[1],
                                                     "text": (texts.get(key[1]) or "")[:160], "total": 0, "wrong": 0,
                                                     "comments": []})
                    st["total"] += 1
                    if it.get("verdict") in ("incorrect", "partial", "missing"):
                        st["wrong"] += 1
                        if it.get("comment") and len(st["comments"]) < 3:
                            st["comments"].append(it["comment"][:160])
        hardest_items = sorted(
            ({**v, "error_rate_percent": round(v["wrong"] / v["total"] * 100)} for v in item_stats.values()
             if v["total"] >= 2),
            key=lambda v: -v["error_rate_percent"],
        )[:6]
        ranked = sorted((a for a in per_assignment if a["avg_percent"] is not None), key=lambda a: a["avg_percent"])
        return {"group": g.name, "assignments": per_assignment, "hardest_assignments": ranked[:3],
                "hardest_items": hardest_items}

    async def create_assignment(self, group_id: str, topic: str, count: int = 10, difficulty: str = "medium",
                                due_in_days: int = 3, wishes: str | None = None) -> dict:
        from datetime import datetime, timedelta

        from app.core.errors import AppError
        from app.services import assignments as svc

        groups = {str(g.id): g for g in await self._groups()}
        g = groups.get(group_id)
        if g is None:
            return {"error": "Guruh topilmadi. Avval list_groups chaqiring"}
        if difficulty not in ("easy", "medium", "hard"):
            difficulty = "medium"
        days = max(1, min(int(due_in_days or 3), 30))
        local = datetime.now(TASHKENT).replace(hour=20, minute=0, second=0, microsecond=0) + timedelta(days=days)
        topic = (topic or "").strip()[:120] or "Mashqlar"
        try:
            a = await svc.create_assignment(
                self.db, self.teacher, group_id=g.id, title=topic, instructions=(wishes or "").strip() or None,
                source_type="ai", due_at=local, allow_late=True, late_penalty_percent=0,
                ai_params={"topic": topic, "count": int(count or 10), "difficulty": difficulty},
            )
        except AppError as exc:
            return {"error": exc.message}
        self.attachments.append({"type": "assignment", "assignment_id": str(a.id), "title": a.title,
                                 "group_name": g.name, "count": int(count or 10), "difficulty": difficulty,
                                 "due_at": a.due_at.isoformat()})
        return {"created": True, "assignment_id": str(a.id), "status": "draft_preparing",
                "note": "AI misollarni tayyorlamoqda (1-2 daqiqa). Tayyor bo'lgach ustoz ko'rib chiqib e'lon qiladi; "
                        "e'lon qilinmaguncha o'quvchilar ko'rmaydi."}

    async def call(self, name: str, args: dict) -> dict:
        match name:
            case "list_groups":
                return await self.list_groups()
            case "find_students":
                return await self.find_students(str(args.get("query", "")))
            case "student_report":
                return await self.student_report(str(args.get("student_id", "")))
            case "group_report":
                return await self.group_report(str(args.get("group_id", "")))
            case "students_below":
                return await self.students_below(str(args.get("group_id", "")), args.get("threshold", 70),
                                                 args.get("last_n", 3))
            case "difficult_topics":
                return await self.difficult_topics(str(args.get("group_id", "")), args.get("last_n", 5))
            case "create_assignment":
                return await self.create_assignment(
                    str(args.get("group_id", "")), str(args.get("topic", "")), args.get("count", 10),
                    str(args.get("difficulty", "medium")), args.get("due_in_days", 3), args.get("wishes"))
        return {"error": f"Noma'lum vosita: {name}"}


TOOL_SPECS = [
    {
        "name": "list_groups",
        "description": "O'qituvchining barcha faol guruhlari: id, nomi, fani, o'quvchilar soni.",
        "parameters": {"type": "object", "properties": {}},
    },
    {
        "name": "find_students",
        "description": "O'quvchini ismi yoki familiyasi bo'yicha qidiradi (faqat shu o'qituvchining guruhlarida).",
        "parameters": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "Ism, familiya yoki ularning qismi"}},
            "required": ["query"],
        },
    },
    {
        "name": "student_report",
        "description": "O'quvchi bo'yicha aniq tahlil: o'rtacha foiz, o'sish/pasayish, oxirgi baholar, "
                       "topshirmagan vazifalar, kechikishlar, tez-tez qiladigan xatolari, reytingdagi o'rni.",
        "parameters": {
            "type": "object",
            "properties": {"student_id": {"type": "string", "description": "find_students qaytargan student_id"}},
            "required": ["student_id"],
        },
    },
    {
        "name": "group_report",
        "description": "Guruh bo'yicha tahlil: o'rtacha natija, topshirish foizi, eng yaxshilar, e'tibor kerak "
                       "bo'lganlar, vazifalar bo'yicha natijalar, keng tarqalgan xatolar.",
        "parameters": {
            "type": "object",
            "properties": {"group_id": {"type": "string", "description": "list_groups qaytargan group_id"}},
            "required": ["group_id"],
        },
    },
    {
        "name": "students_below",
        "description": "Guruhda oxirgi N ta (muddati o'tgan) vazifa bo'yicha o'rtachasi belgilangan foizdan past "
                       "o'quvchilar va vazifani topshirmaganlar. Masalan: 'oxirgi 3 ta vazifada 70% dan past'.",
        "parameters": {
            "type": "object",
            "properties": {
                "group_id": {"type": "string"},
                "threshold": {"type": "number", "description": "Foiz chegarasi, masalan 70"},
                "last_n": {"type": "integer", "description": "Oxirgi nechta vazifa (standart 3)"},
            },
            "required": ["group_id"],
        },
    },
    {
        "name": "difficult_topics",
        "description": "Guruh qaysi mavzu/vazifada eng ko'p qiynalyapti: vazifalar bo'yicha o'rtacha foiz, "
                       "eng ko'p xato qilingan misollar (xato foizi va AI izohlari bilan).",
        "parameters": {
            "type": "object",
            "properties": {
                "group_id": {"type": "string"},
                "last_n": {"type": "integer", "description": "Oxirgi nechta vazifa (standart 5)"},
            },
            "required": ["group_id"],
        },
    },
    {
        "name": "create_assignment",
        "description": "Guruhga AI yaratgan misollar bilan yangi vazifa QORALAMASINI tuzadi (mavzu, soni, qiyinligi). "
                       "Faqat ustoz aniq so'raganda chaqiring. Ustoz ko'rib chiqib e'lon qilmaguncha o'quvchilar ko'rmaydi.",
        "parameters": {
            "type": "object",
            "properties": {
                "group_id": {"type": "string"},
                "topic": {"type": "string", "description": "Mavzu, masalan 'Kasrlarni qo'shish'"},
                "count": {"type": "integer", "description": "Misollar soni (1-40)"},
                "difficulty": {"type": "string", "enum": ["easy", "medium", "hard"]},
                "due_in_days": {"type": "integer", "description": "Necha kundan keyin topshirish (standart 3)"},
                "wishes": {"type": "string", "description": "Ustozning qo'shimcha istaklari (ixtiyoriy)"},
            },
            "required": ["group_id", "topic", "count", "difficulty"],
        },
    },
]
