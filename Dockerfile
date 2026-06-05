# Filipino Sentiment Inference API — AWS Lambda container image.
#
# NOTE ON ALPINE: PyTorch publishes only glibc (manylinux) wheels, which are
# incompatible with Alpine's musl libc. Installing torch on Alpine forces a slow
# source build and a bloated image. We therefore use the official Debian-slim
# Python image (glibc) and rely on the AWS Lambda Web Adapter to bridge HTTP to
# the Lambda runtime — the production-standard approach for PyTorch on Lambda.
#
# Build:  docker build -t filipino-sentiment-api .
# Run:    docker run -p 9000:8080 filipino-sentiment-api

# ---------------------------------------------------------------------------
# Stage 1: builder — install Python deps into an isolated prefix.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Install CPU-only torch from the dedicated index, then the rest of the deps.
COPY requirements.txt .
RUN pip install --prefix=/install \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: runtime — slim image with the Lambda Web Adapter + app + models.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS runtime

# Lambda Web Adapter: lets a standard HTTP server (uvicorn) run on Lambda.
# It listens on the Lambda Runtime API and proxies to PORT (default 8080).
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.0.1 \
     /lambda-adapter /opt/extensions/lambda-adapter

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Lambda Web Adapter configuration.
    PORT=8080 \
    AWS_LWA_READINESS_CHECK_PATH=/health \
    AWS_LWA_INVOKE_MODE=buffered \
    # App configuration: models are baked into the image at /var/task/models.
    MODELS_DIR=/var/task/models \
    INFERENCE_DEVICE=cpu \
    # Keep HF offline at runtime — weights are local, never reach the network.
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    HF_HOME=/tmp/hf

# Create the non-root user up front so we can COPY --chown directly and avoid a
# second 2 GB layer from a separate `chown -R` over the models.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

# Copy installed Python packages from the builder stage.
COPY --from=builder /install /usr/local

WORKDIR /var/task

# Application code and trained models (owned by the runtime user as they land).
COPY --chown=appuser:appuser api/ ./api/
COPY --chown=appuser:appuser models/teacher_model/ ./models/teacher_model/
COPY --chown=appuser:appuser models/student_model/ ./models/student_model/

# Run as a non-root user (Lambda allows this; good container hygiene).
USER appuser

EXPOSE 8080

# Single worker: model weights are large and each worker would duplicate them
# in memory. Lambda scales by concurrent containers, not in-process workers.
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
