"""Teacher model (XLM-RoBERTa-Base) inference routes."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from api.config import get_settings
from api.inference import get_registry
from api.schemas import PredictRequest, PredictResponse

router = APIRouter(prefix="/teacher", tags=["teacher"])

MODEL_NAME = "teacher"


@router.post("/predict", response_model=PredictResponse, summary="Teacher sentiment prediction")
def predict(request: PredictRequest) -> PredictResponse:
    """Classify Filipino review texts with the XLM-RoBERTa teacher model."""
    settings = get_settings()
    if len(request.texts) > settings.max_batch_size:
        raise HTTPException(
            status_code=413,
            detail=f"Batch too large: {len(request.texts)} > {settings.max_batch_size}",
        )

    model = get_registry().get(MODEL_NAME)
    predictions = model.predict(request.texts)
    return PredictResponse(model=MODEL_NAME, predictions=predictions)
