def make(client, **overrides):
    body = {"title": "Lunch", "amount": 250.5, "category": "food", "spent_on": "2026-10-01"}
    body.update(overrides)
    return client.post("/api/expenses", json=body)


def test_health_and_ready(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json() == {"status": "ready"}


def test_create_expense_returns_201_and_id(client):
    r = make(client)
    assert r.status_code == 201
    data = r.json()
    assert data["id"] >= 1 and data["title"] == "Lunch" and data["amount"] == 250.5


def test_create_rejects_non_positive_amount(client):
    assert make(client, amount=0).status_code == 422
    assert make(client, amount=-5).status_code == 422


def test_list_and_filter_by_category(client):
    make(client, title="Lunch", category="food")
    make(client, title="Metro", category="travel", amount=40)
    assert len(client.get("/api/expenses").json()) == 2
    food = client.get("/api/expenses", params={"category": "food"}).json()
    assert [e["title"] for e in food] == ["Lunch"]


def test_get_update_delete_roundtrip(client):
    created = make(client).json()
    url = f"/api/expenses/{created['id']}"
    assert client.get(url).json()["title"] == "Lunch"
    updated = client.put(url, json={"title": "Dinner", "amount": 400, "category": "food", "spent_on": "2026-10-02"})
    assert updated.status_code == 200 and updated.json()["title"] == "Dinner"
    assert client.delete(url).status_code == 204
    assert client.get(url).status_code == 404


def test_missing_expense_returns_404(client):
    assert client.get("/api/expenses/999").status_code == 404
    assert client.delete("/api/expenses/999").status_code == 404


def test_summary_totals_by_category(client):
    make(client, amount=100, category="food")
    make(client, amount=50, category="food")
    make(client, amount=30, category="travel")
    s = client.get("/api/summary").json()
    assert s["total"] == 180 and s["count"] == 3
    assert s["by_category"][0] == {"category": "food", "total": 150, "count": 2}


def test_metrics_endpoint_exposes_prometheus_format(client):
    client.get("/health")
    body = client.get("/metrics").text
    assert "expensetrail_http_requests_total" in body
    assert 'path="/health"' in body
