"""AI javoblarining qat'iy tuzilmasi (structured outputs). Model faqat shu shaklda javob qaytaradi."""

from typing import Literal

from pydantic import BaseModel, Field


class ExtractedItem(BaseModel):
    number: str = Field(description="Misol raqami kitobdagidek, masalan '56' yoki '3a'")
    text: str = Field(description="Misol sharti to'liq, formulalar oddiy matnda (x^2, sqrt(x), 3/4)")
    answer: str | None = Field(description="To'g'ri javob, agar ishonch bilan yechilsa; aks holda null")


class ExtractedItems(BaseModel):
    items: list[ExtractedItem]
    notes: str | None = Field(description="Ustozga eslatma: o'qib bo'lmagan joylar, topilmagan raqamlar va h.k.")


class GeneratedItem(BaseModel):
    number: str = Field(description="Tartib raqami: '1', '2', ...")
    text: str = Field(description="Misol sharti. Matematik ifodalar LaTeX'da, $...$ ichida")
    answer: str = Field(description="Aniq to'g'ri javob (matematikada LaTeX, $...$ ichida)")


class GeneratedSet(BaseModel):
    items: list[GeneratedItem]
    notes: str | None = Field(description="Ustozga qisqa eslatma (o'zbekcha) yoki null")


class RubricCriterion(BaseModel):
    name: str
    weight: int = Field(description="Foiz; barcha mezonlar yig'indisi 100")
    description: str


class Rubric(BaseModel):
    criteria: list[RubricCriterion]


Verdict = Literal["correct", "partial", "incorrect", "missing"]


class GradedItem(BaseModel):
    number: str
    verdict: Verdict
    student_answer: str = Field(
        description="O'quvchi yozgan yakuniy javob, qisqa (40 belgigacha). Topilmasa bo'sh. "
        "\"Nega?\" tushuntirishi rasmni qayta yubormasdan shundan foydalanadi"
    )
    comment: str = Field(description="Ustoz uchun 3-8 so'z: xato qayerda. To'g'ri bo'lsa bo'sh")


class GradeResult(BaseModel):
    matches_assignment: bool = Field(description="Yuborilgan ish aynan shu vazifaga tegishlimi")
    items: list[GradedItem]
    score_percent: int = Field(description="0-100")
    feedback_student: str = Field(description="O'quvchiga bitta qisqa rag'bat gapi (xatolarni tushuntirmaydi)")
    note_teacher: str = Field(description="Ustozga bitta gap: o'quvchi nimada qiynalyapti")
    confidence: float = Field(description="0.0-1.0: rasm sifati va baholash ishonchliligi")


class Explanation(BaseModel):
    text: str = Field(description="O'quvchiga 2-3 ta juda sodda gap: nega xato va to'g'ri yo'l qanday")
