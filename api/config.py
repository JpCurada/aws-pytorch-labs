"""Application configuration.

Values are read from environment variables so the same image can run locally,
in a container, and on AWS Lambda without code changes. Defaults assume the
models are baked into the image under ``/var/task/models`` (Lambda) which maps
to ``<repo>/models`` during local development.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

# Load a local .env file if one exists, so `cp .env.example .env` just works for
# local development. This is a no-op when python-dotenv is not installed or no
# .env is present (e.g. on AWS Lambda, where env vars come from the platform).
# Real environment variables always take precedence over .env values.
try:
    from dotenv import load_dotenv

    load_dotenv(override=False)
except ImportError:
    pass


class Settings:
    """Runtime settings resolved from the environment."""

    def __init__(self) -> None:
        # Root that contains ``teacher_model/`` and ``student_model/`` folders.
        # On Lambda the image working dir is /var/task; locally we fall back to
        # the repo's ./models directory relative to this file.
        default_models_dir = Path(__file__).resolve().parent.parent / "models"
        self.models_dir: Path = Path(os.getenv("MODELS_DIR", str(default_models_dir)))

        self.teacher_model_path: Path = Path(
            os.getenv("TEACHER_MODEL_PATH", str(self.models_dir / "teacher_model"))
        )
        self.student_model_path: Path = Path(
            os.getenv("STUDENT_MODEL_PATH", str(self.models_dir / "student_model"))
        )

        # Max token length must match training (notebook used 128).
        self.max_length: int = int(os.getenv("MAX_LENGTH", "128"))

        # Force CPU on Lambda; allow override for GPU dev boxes.
        self.device: str = os.getenv("INFERENCE_DEVICE", "cpu")

        # Cap batch size to protect Lambda memory on large request payloads.
        self.max_batch_size: int = int(os.getenv("MAX_BATCH_SIZE", "32"))

        # Human-readable class labels (index order matches training: 0=neg, 1=pos).
        self.labels: list[str] = ["negative", "positive"]

        # Limit intra-op threads; Lambda gives ~2 vCPU per 1769MB of memory.
        self.torch_num_threads: int = int(os.getenv("TORCH_NUM_THREADS", "0"))


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return a cached Settings instance."""
    return Settings()
