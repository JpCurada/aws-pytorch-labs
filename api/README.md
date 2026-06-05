# Filipino Sentiment Inference API

FastAPI service that serves the two models from the knowledge-distillation
notebook for **Filipino sentiment analysis**:

- **Teacher** — XLM-RoBERTa-Base (`/teacher/predict`)
- **Student** — distilled DistilBERT-Base-Multilingual (`/student/predict`)

It runs locally with `uvicorn` and deploys unchanged to **AWS Lambda** as a
container image via the **Lambda Web Adapter**.

---

## Layout

```
api/
├── main.py            # FastAPI app: mounts routers, /health, /
├── config.py          # Env-driven settings (paths, max_length, device, batch)
├── schemas.py         # Pydantic request/response models
├── inference.py       # Lazy, thread-safe model registry + inference
├── teacher/router.py  # POST /teacher/predict
└── student/router.py  # POST /student/predict
```

Models are loaded **lazily** on first request to each route and cached for the
life of the process (one cold-start load per Lambda container, reused warm).

---

## API

### `POST /teacher/predict` · `POST /student/predict`

Request:

```json
{ "texts": ["Magandang produkto!", "Napakasama ng quality"] }
```

Response:

```json
{
  "model": "student",
  "predictions": [
    {
      "text": "Magandang produkto!",
      "label": "positive",
      "score": 0.978,
      "probabilities": { "negative": 0.022, "positive": 0.978 }
    }
  ]
}
```

### `GET /health`

Returns `{"status":"ok","models_loaded":{"teacher":false,"student":true}}`.
Used as the Lambda Web Adapter readiness check.

Interactive docs at `GET /docs` (Swagger UI).

---

## Run locally (Docker)

The recommended way to run the API is in Docker — no Python setup required. The
image bundles Python, PyTorch, the API, and the models.

> Make sure the model weights are present first. They are stored in Git LFS, so
> run `git lfs pull` after cloning. If `models/teacher_model/model.safetensors`
> is only a few hundred bytes, you still have a pointer file, not the model.

```bash
make build            # docker build -t filipino-sentiment:latest .
make docker-run       # runs on host :9000 -> container :8080
```

Then open `http://localhost:9000/docs`, or:

```bash
curl -X POST http://localhost:9000/student/predict \
  -H "content-type: application/json" \
  -d '{"texts": ["Magandang produkto!", "Napakasama ng quality"]}'
```

> **Why Debian-slim, not Alpine?** PyTorch ships only glibc (manylinux) wheels.
> Alpine uses musl libc, so `pip install torch` there triggers a slow source
> build and a bloated image. Debian-slim + the Lambda Web Adapter is the
> standard, reliable way to run PyTorch on Lambda.

### Optional: running without Docker (for code development)

If you are editing the API code and want hot reload, you can run it directly with
Python 3.12 instead. This is optional and not required to use the service.

```bash
pip install --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt
uvicorn api.main:app --reload --port 8080
python scripts/smoke_test.py http://localhost:8080
```

---

## Deploy to AWS Lambda (container)

Split flow: **Terraform** provisions AWS resources, the **Makefile** ships the
image. See [`infra/README.md`](../infra/README.md) for the full walkthrough.

```bash
# First time (ECR must exist before the image is pushed, image before Lambda):
cd infra && terraform init && terraform apply -target=aws_ecr_repository.this
cd .. && make build && make push-ecr
cd infra && terraform apply           # IAM, logs, Lambda, Function URL
terraform output -raw function_url

# Subsequent code changes (no terraform needed — image_uri drift is ignored):
make build && make push-ecr && make deploy
```

The Lambda Web Adapter handles the HTTP ⇄ Lambda translation automatically —
no handler code required. Sizing defaults (memory 3008 MB, timeout 120 s, /tmp
512 MB) are set in `infra/variables.tf`.

### Configuration (environment variables)

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODELS_DIR` | `/var/task/models` | Root holding `teacher_model/`, `student_model/` |
| `TEACHER_MODEL_PATH` | `$MODELS_DIR/teacher_model` | Override teacher path |
| `STUDENT_MODEL_PATH` | `$MODELS_DIR/student_model` | Override student path |
| `MAX_LENGTH` | `128` | Tokenizer max length (matches training) |
| `MAX_BATCH_SIZE` | `32` | Reject oversized batches (HTTP 413) |
| `INFERENCE_DEVICE` | `cpu` | `cpu` on Lambda; `cuda` on a GPU dev box |
| `TORCH_NUM_THREADS` | `0` (auto) | Pin intra-op threads to Lambda vCPUs |
| `PRELOAD_MODELS` | `false` | Warm both models at startup vs lazy-load |
| `AWS_LWA_READINESS_CHECK_PATH` | `/health` | Web Adapter readiness probe |

---

## Cold-start notes

- First request to each route loads ~0.9–1.1 GB of weights from the image
  layer; subsequent warm requests are fast.
- The image embeds both models (~2 GB). The 10 GB Lambda image limit easily
  accommodates this.
- Set `PRELOAD_MODELS=true` to load both at container start if you prefer a
  slower cold start but a fast first request. For lowest p99 on a hot path,
  consider **provisioned concurrency**.

---

## Where this fits

- The models served here are produced by [`../notebooks/README.md`](../notebooks/README.md)
  and stored in `../models/`.
- The deployment (Terraform, ECR, Lambda) is described in
  [`../infra/README.md`](../infra/README.md).

See the [project README](../README.md) for the full setup guide.
