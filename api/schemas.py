"""Pydantic request/response models shared by both routers."""
from __future__ import annotations

from typing import List

from pydantic import BaseModel, Field, field_validator


class PredictRequest(BaseModel):
    """A batch (or single) of Filipino review texts to score."""

    texts: List[str] = Field(
        ...,
        min_length=1,
        description="One or more review texts to classify.",
        examples=[["Magandang produkto!", "Napakasama ng quality"]],
    )

    @field_validator("texts")
    @classmethod
    def _strip_and_validate(cls, value: List[str]) -> List[str]:
        cleaned = [t.strip() for t in value]
        if any(not t for t in cleaned):
            raise ValueError("texts must not contain empty or whitespace-only strings")
        return cleaned


class Prediction(BaseModel):
    """Sentiment prediction for a single text."""

    text: str
    label: str = Field(description="Predicted sentiment label.")
    score: float = Field(description="Confidence of the predicted label (0-1).")
    probabilities: dict[str, float] = Field(
        description="Per-class probabilities keyed by label name."
    )


class PredictResponse(BaseModel):
    """Inference response for a batch of texts."""

    model: str = Field(description="Which model produced these predictions.")
    predictions: List[Prediction]


class HealthResponse(BaseModel):
    status: str
    models_loaded: dict[str, bool]
