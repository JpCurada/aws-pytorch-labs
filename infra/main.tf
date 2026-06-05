###############################################################################
# Filipino Sentiment Inference API — AWS infrastructure (split deploy flow).
#
# Terraform provisions ONLY the AWS resources:
#   1. ECR repository (+ scan + lifecycle).
#   2. IAM role and CloudWatch Logs group.
#   3. Lambda function (container image) and Function URL.
#
# The Docker image is built, pushed, and rolled out by the Makefile, OUT of
# Terraform's critical path:
#   make build       # docker build
#   make push-ecr    # login + push image tag to ECR  (run BEFORE first apply)
#   terraform apply  # create/refresh infra against the pushed tag
#   make deploy      # aws lambda update-function-code -> point Lambda at new image
#
# Ordering for a clean first run:
#   make push-ecr  →  terraform apply   (image must exist before Lambda is created)
# Thereafter, code changes are: make build → make push-ecr → make deploy.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # The image tag Terraform expects in ECR. Defaults to "latest"; override with
  # -var image_tag=... to pin a specific tag (recommended for prod).
  image_tag = coalesce(var.image_tag, "latest")
  image_uri = "${aws_ecr_repository.this.repository_url}:${local.image_tag}"
}

###############################################################################
# ECR repository
###############################################################################

resource "aws_ecr_repository" "this" {
  name = var.project_name
  # MUTABLE so `make push-ecr` can re-push the same tag (e.g. "latest").
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the most recent images to control storage cost.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

###############################################################################
# IAM role for the Lambda function
###############################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "basic_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# CloudWatch log group (created explicitly so retention is managed by TF)
###############################################################################

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = var.log_retention_days
}

###############################################################################
# Lambda function (container image)
#
# image_uri points at the tag pushed by `make push-ecr`. After creation, the
# image is rolled out by `make deploy` (aws lambda update-function-code), so we
# ignore subsequent image_uri drift to avoid Terraform fighting the Makefile.
###############################################################################

resource "aws_lambda_function" "this" {
  function_name = var.project_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = local.image_uri

  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_s
  architectures = ["x86_64"]

  ephemeral_storage {
    size = var.lambda_ephemeral_mb
  }

  environment {
    variables = {
      MODELS_DIR       = "/var/task/models"
      INFERENCE_DEVICE = "cpu"
      PRELOAD_MODELS   = tostring(var.preload_models)
      # The Web Adapter's readiness check path (matches the Dockerfile default).
      AWS_LWA_READINESS_CHECK_PATH = "/health"
    }
  }

  lifecycle {
    # `make deploy` updates the running image out-of-band; don't revert it.
    ignore_changes = [image_uri]
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_logs,
    aws_cloudwatch_log_group.lambda,
  ]
}

###############################################################################
# Function URL — HTTPS endpoint for the API
###############################################################################

resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = var.function_url_auth

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type"]
    max_age       = 86400
  }
}

# A public (authorization_type = NONE) Function URL still returns 403 unless a
# resource-based permission allows anonymous invoke. This grants it, but only
# when the URL is public — for AWS_IAM the permission is neither created nor
# needed (count = 0).
resource "aws_lambda_permission" "function_url_public" {
  count = var.function_url_auth == "NONE" ? 1 : 0

  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
