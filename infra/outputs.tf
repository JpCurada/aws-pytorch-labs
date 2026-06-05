output "function_url" {
  description = "HTTPS endpoint for the inference API. Append /teacher/predict, /student/predict, /health, or /docs."
  value       = aws_lambda_function_url.this.function_url
}

output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "ecr_repository_url" {
  description = "ECR repository hosting the image."
  value       = aws_ecr_repository.this.repository_url
}

output "image_uri" {
  description = "Image URI (tag) that was built and deployed."
  value       = local.image_uri
}

output "log_group" {
  description = "CloudWatch Logs group for the function."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "auth_type" {
  description = "Function URL auth type. With AWS_IAM, requests must be SigV4-signed."
  value       = aws_lambda_function_url.this.authorization_type
}
