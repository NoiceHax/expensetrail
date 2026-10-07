import datetime as dt

from pydantic import BaseModel, ConfigDict, Field


class ExpenseIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    amount: float = Field(gt=0)
    category: str = Field(default="other", min_length=1, max_length=40)
    spent_on: dt.date = Field(default_factory=dt.date.today)


class ExpenseOut(ExpenseIn):
    model_config = ConfigDict(from_attributes=True)
    id: int


class CategoryTotal(BaseModel):
    category: str
    total: float
    count: int


class Summary(BaseModel):
    total: float
    count: int
    by_category: list[CategoryTotal]
