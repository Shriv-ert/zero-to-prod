# zero-to-prod

A small FastAPI service taken all the way to production:
tests on every PR, container image on every merge, Terraform-managed AWS host,
Prometheus + Grafana dashboards.

## Run locally

    python3.12 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    uvicorn app.main:app --reload

Then open http://localhost:8000/docs