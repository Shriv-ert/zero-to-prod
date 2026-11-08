# tests/test_main.py
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_returns_default_greeting():
    r = client.get("/")
    assert r.status_code == 200
    assert "message" in r.json()


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_metrics_exposed():
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text