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
    comment: str = Field(description="Qisqa izoh: xato qayerda. To'g'ri bo'lsa bo'sh qoldirish mumkin")


class GradeResult(BaseModel):
    matches_assignment: bool = Field(description="Yuborilgan ish aynan shu vazifaga tegishlimi")
    items: list[GradedItem]
    score_percent: int = Field(description="0-100")
    feedback_student: str = Field(description="O'quvchiga 2-4 gaplik iliq, aniq izoh")
    note_teacher: str = Field(description="Ustozga 1-2 gaplik xulosa: o'quvchi nimada qiynalyapti")
    confidence: float = Field(description="0.0-1.0: rasm sifati va baholash ishonchliligi")
