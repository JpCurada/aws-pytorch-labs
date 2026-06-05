variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "filipino-sentiment"
}

variable "lambda_memory_mb" {
  description = "Lambda memory (MB). More memory also grants more vCPU, speeding up PyTorch inference. ~3008+ recommended for both models."
  type        = number
  default     = 3008

  validation {
    condition     = var.lambda_memory_mb >= 1769 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 1769 and 10240."
  }
}

variable "lambda_timeout_s" {
  description = "Lambda timeout (seconds). Must cover cold-start model load."
  type        = number
  default     = 120
}

variable "lambda_ephemeral_mb" {
  description = "Ephemeral /tmp storage (MB). Weights are baked into the image, so the default is plenty."
  type        = number
  default     = 512
}

variable "preload_models" {
  description = "If true, both models load at container start (slower cold start, faster first request)."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the function."
  type        = number
  default     = 14
}

variable "function_url_auth" {
  description = "Auth type for the Lambda Function URL: NONE (public, no auth) or AWS_IAM (SigV4-signed requests only). NONE makes the endpoint callable by anyone with the URL."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth)
    error_message = "function_url_auth must be NONE or AWS_IAM."
  }
}

variable "image_tag" {
  description = "Tag for the built container image. Defaults to a content hash for immutable, change-triggered deploys."
  type        = string
  default     = null
}
