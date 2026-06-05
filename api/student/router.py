"""Student model (DistilBERT-Base-Multilingual, distilled) inference routes."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from api.config import get_settings
from api.inference import get_registry
from api.schemas import PredictRequest, PredictResponse

router = APIRouter(prefix="/student", tags=["student"])

MODEL_NAME = "student"


@router.post("/predict", response_model=PredictResponse, summary="Student sentiment prediction")
def predict(request: PredictRequest) -> PredictResponse:
    """Classify Filipino review texts with the distilled student model."""
    settings = get_settings()
    if len(request.texts) > settings.max_batch_size:
        raise HTTPException(
            status_code=413,
            detail=f"Batch too large: {len(request.texts)} > {settings.max_batch_size}",
        )

    model = get_registry().get(MODEL_NAME)
    predictions = model.predict(request.texts)
    return PredictResponse(model=MODEL_NAME, predictions=predictions)
