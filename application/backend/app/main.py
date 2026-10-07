import time

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from .db import get_db
from .models import Expense
from .schemas import CategoryTotal, ExpenseIn, ExpenseOut, Summary

app = FastAPI(title="ExpenseTrail API", version="1.0.0")

REQUESTS = Counter("expensetrail_http_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("expensetrail_http_request_seconds", "HTTP request latency", ["method", "path"])


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    path = route.path if route else "unmatched"   # route template, so /expenses/7 and /expenses/8 share a label
    LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
    REQUESTS.labels(request.method, path, str(response.status_code)).inc()
    return response


@app.get("/health")
def health():
    """Liveness: the process is up."""
    return {"status": "ok"}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    """Readiness: the database answers."""
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        raise HTTPException(status_code=503, detail="database unavailable")
    return {"status": "ready"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/expenses", response_model=list[ExpenseOut])
def list_expenses(category: str | None = None, db: Session = Depends(get_db)):
    query = select(Expense).order_by(Expense.spent_on.desc(), Expense.id.desc())
    if category:
        query = query.where(Expense.category == category)
    return db.scalars(query).all()


@app.post("/api/expenses", response_model=ExpenseOut, status_code=201)
def create_expense(payload: ExpenseIn, db: Session = Depends(get_db)):
    expense = Expense(**payload.model_dump())
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return expense


@app.get("/api/expenses/{expense_id}", response_model=ExpenseOut)
def get_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = db.get(Expense, expense_id)
    if expense is None:
        raise HTTPException(status_code=404, detail="expense not found")
    return expense


@app.put("/api/expenses/{expense_id}", response_model=ExpenseOut)
def update_expense(expense_id: int, payload: ExpenseIn, db: Session = Depends(get_db)):
    expense = db.get(Expense, expense_id)
    if expense is None:
        raise HTTPException(status_code=404, detail="expense not found")
    for field, value in payload.model_dump().items():
        setattr(expense, field, value)
    db.commit()
    db.refresh(expense)
    return expense


@app.delete("/api/expenses/{expense_id}", status_code=204)
def delete_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = db.get(Expense, expense_id)
    if expense is None:
        raise HTTPException(status_code=404, detail="expense not found")
    db.delete(expense)
    db.commit()
    return Response(status_code=204)


@app.get("/api/summary", response_model=Summary)
def summary(db: Session = Depends(get_db)):
    rows = db.execute(
        select(Expense.category, func.sum(Expense.amount), func.count(Expense.id))
        .group_by(Expense.category)
        .order_by(func.sum(Expense.amount).desc())
    ).all()
    by_category = [CategoryTotal(category=c, total=round(t, 2), count=n) for c, t, n in rows]
    return Summary(
        total=round(sum(c.total for c in by_category), 2),
        count=sum(c.count for c in by_category),
        by_category=by_category,
    )
