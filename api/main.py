"""FastAPI application entrypoint.

Serves inference for the Filipino sentiment teacher (XLM-RoBERTa) and student
(distilled DistilBERT) models. Designed to run behind the AWS Lambda Web
Adapter in a container, and identically via ``uvicorn`` for local development.
"""
from __future__ import annotations

import logging
import os

from fastapi import FastAPI

from api.config import get_settings
from api.inference import get_registry
from api.schemas import HealthResponse
from api.student.router import router as student_router
from api.teacher.router import router as teacher_router

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

app = FastAPI(
    title="Filipino Sentiment Inference API",
    description=(
        "Cross-lingual knowledge-distillation sentiment analysis. "
        "Exposes the XLM-RoBERTa teacher and the distilled DistilBERT student."
    ),
    version="1.0.0",
)

app.include_router(teacher_router)
app.include_router(student_router)


@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    """Liveness/readiness probe. Reports which models are loaded in memory."""
    return HealthResponse(status="ok", models_loaded=get_registry().status())


@app.get("/", tags=["meta"])
def root() -> dict[str, object]:
    """Service metadata and available routes."""
    return {
        "service": "filipino-sentiment-inference",
        "version": app.version,
        "models": ["teacher", "student"],
        "routes": ["/teacher/predict", "/student/predict", "/health", "/docs"],
    }


if os.getenv("PRELOAD_MODELS", "false").lower() == "true":
    # Optional: warm both models at startup to trade a slower cold start for a
    # faster first request. Off by default so /health stays cheap.
    registry = get_registry()
    for _name in ("teacher", "student"):
        try:
            registry.get(_name)
        except Exception as exc:  # noqa: BLE001 - log and continue, fail lazily per route
            logging.getLogger("api.main").warning("Preload of %s failed: %s", _name, exc)
