# app/main.py
import os

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="zero-to-prod")
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


@app.get("/")
def root():
    return {"message": os.environ.get("GREETING", "hello from zero-to-prod")}


@app.get("/health")
def health():
    return {"status": "ok"}