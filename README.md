# Filipino Sentiment Analysis with Cross-Lingual Knowledge Distillation

An end-to-end project that trains, distills, and **deploys** a Filipino product-review
sentiment classifier. A large multilingual model (the *teacher*) is compressed into a
smaller, faster model (the *student*) through knowledge distillation, and both are served
through a single API that runs locally or on **AWS Lambda**.

This repository is meant to be read as a **learning guide**: each folder is a stage of the
workflow, and each folder has its own README explaining that stage in detail.

---

## What you will learn

- How **knowledge distillation** transfers knowledge from a big model to a small one.
- How to fine-tune and evaluate transformer models for a **low-resource language** (Filipino).
- How to wrap models in a clean **FastAPI** inference service.
- How to package a PyTorch app as a **container** and deploy it to **AWS Lambda** with
  the Lambda Web Adapter.
- How to manage large model files with **Git LFS** and infrastructure with **Terraform**.

You do not need to be an expert in all of these. Start at the top and follow the links.

---

## Repository layout

```
aws-pytorch-labs/
├── README.md              # You are here
├── Dockerfile             # Container image for the API (Debian-slim + Lambda Web Adapter)
├── Makefile               # Build, run, and deploy commands
├── requirements.txt       # Python dependencies for the API
├── .gitattributes         # Git LFS rules for large model files
│
├── data/                  # Raw dataset + README
│   └── reviews.json
├── notebooks/             # Training + distillation notebook + README
│   └── cdlk-filipino-sentiment.ipynb
├── models/                # Exported models (HuggingFace format, via Git LFS)
│   ├── teacher_model/
│   └── student_model/
├── api/                   # FastAPI inference service + README
│   ├── main.py
│   ├── config.py
│   ├── inference.py
│   ├── schemas.py
│   ├── teacher/
│   └── student/
├── infra/                 # Terraform (ECR, IAM, Lambda, Function URL) + README
└── scripts/
    └── smoke_test.py      # Quick API check
```

---

## The models in one table

| Metric | Teacher (XLM-RoBERTa) | Student (DistilBERT) |
| --- | --- | --- |
| Transformer layers | 12 | 6 |
| Test accuracy | 84.85% | 77.78% |
| Inference time (198 samples) | 0.764 s | 0.406 s (1.88x faster) |
| Knowledge retained | 100% | 91.6% |

Full methodology and results are in [`notebooks/README.md`](notebooks/README.md).

---

## Quick start

The whole API runs inside **Docker** — there is no Python or virtual environment
to set up on your machine. The container already includes Python, PyTorch, the
API code, and the models.

### Prerequisites

- **Git** and **Git LFS** (the model weights are large and stored in LFS)
- **Docker**
- **AWS CLI** and **Terraform** (only needed to deploy)

### 1. Clone and pull the model files

```bash
git clone <repo-url>
cd aws-pytorch-labs

git lfs install
git lfs pull          # downloads the actual model weights (~2 GB)
```

> Without `git lfs pull` you will only have small pointer files in `models/`, and
> the API will fail to load. See [Git LFS notes](#git-lfs-notes) below.

### 2. Build and run the API

```bash
make build            # builds the Docker image (includes models + dependencies)
make docker-run       # runs the API at http://localhost:9000
```

### 3. Try it

Open `http://localhost:9000/docs` for interactive API documentation, or call the
API from another terminal:

```bash
curl -X POST http://localhost:9000/student/predict \
  -H "content-type: application/json" \
  -d '{"texts": ["Magandang produkto!", "Napakasama ng quality"]}'
```

Use `/teacher/predict` for the larger teacher model. Check `/health` to see which
models are loaded.

---

## Common commands

All commands are defined in the [`Makefile`](Makefile). Read that file for the
full list, or use these:

| Command | What it does |
| --- | --- |
| `make build` | Build the Docker image |
| `make docker-run` | Run the API locally in Docker (host port 9000) |
| `make push-ecr` | Push the image to AWS ECR |
| `make deploy` | Point the Lambda function at the latest image |
| `make logs` | Tail the Lambda's CloudWatch logs |
| `make url` | Print the deployed Function URL |
| `make destroy` | Tear down all AWS resources (Lambda, URL, ECR, IAM, logs) |

---

## Deploying to AWS

Deployment is a **split flow**: Terraform creates the cloud resources, and the Makefile
builds and ships the container image. The full step-by-step is in
[`infra/README.md`](infra/README.md).

### First-time deploy

**The order matters.** The Lambda is created from a container image, so the image must
already exist in ECR before you create the function. Run these in order:

```bash
# 1. Create ONLY the ECR repository (an empty container registry)
cd infra
terraform init
terraform apply -target=aws_ecr_repository.this

# 2. Build the image and push it INTO that repository
cd ..
make build
make push-ecr

# 3. Now create the Lambda and everything else (the image now exists)
cd infra
terraform apply
terraform output -raw function_url
```

> **Do not skip step 2.** If you run the full `terraform apply` before pushing an
> image, the Lambda creation fails with
> `Source image ...:latest does not exist. Provide a valid source image.`
> The fix is simply to run `make build && make push-ecr`, then `terraform apply` again.

### Updating after a code change

Once the function exists, new code is just an image swap — no Terraform needed:

```bash
make build && make push-ecr && make deploy
```

### Tearing down

When you are done, remove everything so nothing keeps running or accruing cost:

```bash
make destroy
```

This deletes the Lambda function, its public URL, the ECR repository (and the
image inside it), the IAM role, and the log group. Your locally built Docker
image stays on your machine; remove it too with `make clean` if you want.

---

## Git LFS notes

The two `model.safetensors` files are about 1.1 GB and 942 MB, which exceed GitHub's
100 MB per-file limit. They are therefore stored with **Git LFS** (configured in
[`.gitattributes`](.gitattributes)).

- After cloning, always run `git lfs pull` to download the real weights.
- If `models/teacher_model/model.safetensors` is only a few hundred bytes, you have a
  pointer file, not the model. Run `git lfs pull`.
- Pushing the weights consumes LFS storage and bandwidth on your remote. GitHub's free
  tier includes 1 GB of each, so the ~2 GB of weights may require a paid LFS data pack
  or storing the weights elsewhere (for example, Amazon S3).

The deployment does not depend on the remote: `make build` reads the weights from your
local `models/` directory and bakes them into the image.

---

## Where to go next

- New to the project? Read [`notebooks/README.md`](notebooks/README.md) to understand
  how the models were built.
- Want to use the models? Read [`api/README.md`](api/README.md).
- Ready to deploy? Read [`infra/README.md`](infra/README.md).

---

## Author

John Paul Curada.
