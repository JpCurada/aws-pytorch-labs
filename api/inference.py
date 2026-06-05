"""Model loading and inference.

Models are loaded lazily and cached for the lifetime of the process. On AWS
Lambda this means weights are read from disk once per container (cold start)
and reused across all subsequent warm invocations.
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Dict, List

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

from api.config import Settings, get_settings
from api.schemas import Prediction

logger = logging.getLogger("api.inference")


class SentimentModel:
    """Wraps a HuggingFace sequence-classification model + tokenizer."""

    def __init__(self, name: str, model_path: Path, settings: Settings) -> None:
        self.name = name
        self.model_path = model_path
        self.settings = settings
        self.device = torch.device(settings.device)

        if not model_path.exists():
            raise FileNotFoundError(
                f"Model directory for '{name}' not found at {model_path}"
            )

        logger.info("Loading %s model from %s", name, model_path)
        self.tokenizer = AutoTokenizer.from_pretrained(str(model_path))
        self.model = AutoModelForSequenceClassification.from_pretrained(str(model_path))
        self.model.to(self.device)
        self.model.eval()

        # Resolve class labels. Prefer a real id2label baked into the model
        # config; fall back to the configured labels only if the config carries
        # HF's default placeholders (LABEL_0/LABEL_1) or none at all. Guard
        # against a label/output-dimension mismatch.
        self.labels = self._resolve_labels()
        num_out = int(self.model.config.num_labels)
        if len(self.labels) != num_out:
            raise ValueError(
                f"'{name}': {len(self.labels)} labels {self.labels} but model "
                f"outputs {num_out} classes"
            )
        logger.info("Loaded %s model on %s with labels %s", name, self.device, self.labels)

    def _resolve_labels(self) -> List[str]:
        id2label = getattr(self.model.config, "id2label", None) or {}
        ordered = [id2label.get(i) for i in range(len(id2label))]
        is_default = all(
            (lbl is None) or str(lbl).upper().startswith("LABEL_") for lbl in ordered
        )
        if not ordered or is_default:
            return list(self.settings.labels)
        return [str(lbl) for lbl in ordered]

    @torch.inference_mode()
    def predict(self, texts: List[str]) -> List[Prediction]:
        """Classify a batch of texts into sentiment labels with probabilities."""
        labels = self.labels

        encodings = self.tokenizer(
            texts,
            truncation=True,
            padding=True,
            max_length=self.settings.max_length,
            return_tensors="pt",
        ).to(self.device)

        logits = self.model(**encodings).logits
        probs = torch.softmax(logits, dim=1)
        pred_idx = torch.argmax(probs, dim=1)

        results: List[Prediction] = []
        for text, p, idx in zip(texts, probs.tolist(), pred_idx.tolist()):
            results.append(
                Prediction(
                    text=text,
                    label=labels[idx],
                    score=round(float(p[idx]), 6),
                    probabilities={
                        labels[i]: round(float(prob), 6) for i, prob in enumerate(p)
                    },
                )
            )
        return results


class ModelRegistry:
    """Thread-safe lazy registry of named models."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._models: Dict[str, SentimentModel] = {}
        self._lock = threading.Lock()
        self._paths = {
            "teacher": settings.teacher_model_path,
            "student": settings.student_model_path,
        }

        if settings.torch_num_threads > 0:
            torch.set_num_threads(settings.torch_num_threads)

    def get(self, name: str) -> SentimentModel:
        """Return the requested model, loading it on first access."""
        if name in self._models:
            return self._models[name]
        with self._lock:
            if name not in self._models:  # double-checked locking
                if name not in self._paths:
                    raise KeyError(f"Unknown model '{name}'")
                self._models[name] = SentimentModel(
                    name, self._paths[name], self._settings
                )
            return self._models[name]

    def status(self) -> Dict[str, bool]:
        return {name: name in self._models for name in self._paths}


_registry: ModelRegistry | None = None
_registry_lock = threading.Lock()


def get_registry() -> ModelRegistry:
    """Return the process-wide model registry (created once)."""
    global _registry
    if _registry is None:
        with _registry_lock:
            if _registry is None:
                _registry = ModelRegistry(get_settings())
    return _registry
