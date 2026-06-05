# Infrastructure — Terraform

Provisions the AWS resources for the [Filipino Sentiment Inference API](../api/README.md)
on **AWS Lambda** (container image) with an HTTPS **Function URL**.

This is a **split deploy flow**: Terraform owns the AWS resources; the Docker
image is built and shipped by the [`Makefile`](../Makefile), keeping the ~2.5 GB
image build off Terraform's critical path.

Terraform creates:

1. An **ECR** repository (image scanning + lifecycle policy).
2. **IAM** role + **CloudWatch Logs** group.
3. The **Lambda** function (container image) + **Function URL**.

## Files

| File | Purpose |
| --- | --- |
| `versions.tf` | Terraform/AWS provider versions, region, optional S3 backend |
| `variables.tf` | Tunables (region, memory, timeout, auth, retention, image_tag) |
| `main.tf` | ECR, IAM, logs, Lambda, Function URL |
| `outputs.tf` | Function URL, ECR repo, image URI, log group |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and edit |

## Prerequisites

- Terraform ≥ 1.5, AWS credentials configured (`aws sts get-caller-identity` works).
- Docker running locally (for `make build` / `make push-ecr`).
- Trained models present at `../models/teacher_model` and `../models/student_model`
  (baked into the image).

## Deploy — first time

The Lambda is created from a container image, so an image **must exist in ECR
before** `terraform apply` creates the function. Order matters on the first run:

```bash
# 1. Build the image and create the ECR repo, then push.
#    (The repo is created by `terraform apply`, but ECR login/push only needs
#     the repo to exist — so we apply ECR first, OR create the repo then push.)

cd infra
cp terraform.tfvars.example terraform.tfvars     # edit if desired
terraform init
terraform apply -target=aws_ecr_repository.this   # create just the ECR repo

cd ..
make build          # docker build (linux/amd64)
make push-ecr       # login + tag + push :latest to ECR

cd infra
terraform apply     # create IAM, logs, Lambda (from the pushed image), Function URL

terraform output -raw function_url
```

> Why `-target` first: the ECR repo must exist before `make push-ecr`, and the
> Lambda must have an image to point at. Applying the ECR repo, pushing, then
> applying the rest avoids the chicken-and-egg.
>
> If you run the full `terraform apply` before pushing an image, you will see:
> `InvalidParameterValueException: Source image ...:latest does not exist.`
> Recover by running `make build && make push-ecr`, then `terraform apply` again.
> The already-created resources (ECR repo, IAM, log group) are left untouched.

## Deploy — subsequent code changes

Terraform ignores `image_uri` drift (see `main.tf` lifecycle block), so rolling
out new code is just the Makefile — no `terraform apply` needed:

```bash
make build
make push-ecr
make deploy         # aws lambda update-function-code + wait for rollout
```

Run `terraform apply` again only when you change **infra** (memory, timeout,
auth, env vars, etc.).

## Test

```bash
make url            # prints the Function URL

# auth_type = NONE
curl "$(make -s url)health"
curl -X POST "$(make -s url)student/predict" \
  -H 'content-type: application/json' \
  -d '{"texts":["Magandang produkto!","Napakasama ng quality"]}'

make logs           # tail CloudWatch logs
```

> The default `function_url_auth = "NONE"` makes the endpoint **public** — anyone
> with the URL can call it (plain `curl` works, as above). To lock it down, set
> `function_url_auth = "AWS_IAM"` in `terraform.tfvars`; requests then must be
> **SigV4-signed** (e.g. `awscurl`, or `curl --aws-sigv4`).

## Sizing & cost

- **Memory:** more memory grants more vCPU → faster PyTorch inference. Start at
  3008 MB; raise to 4096+ if latency matters.
- **Cold starts:** the first request loads ~1 GB of weights per model. Set
  `preload_models = true` to warm both at container start, or use **provisioned
  concurrency** (not configured here) for a hot path.
- **ECR lifecycle:** keeps only the last 5 images.

## Teardown

```bash
cd infra && terraform destroy
# or, from the repo root:
make destroy
```

`force_delete = true` on the ECR repo lets Terraform remove it with images present.

## Where this fits

This is the final stage. It deploys the API from [`../api/README.md`](../api/README.md),
which serves the models trained in [`../notebooks/README.md`](../notebooks/README.md).

See the [project README](../README.md) for the full setup guide.
