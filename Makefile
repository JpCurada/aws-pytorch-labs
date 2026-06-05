# Filipino Sentiment Inference API — build & deploy.
#
# Deploy flow (split: Terraform provisions infra, make handles the image):
#
#   make build            # docker build the image locally
#   make push-ecr         # create-login-tag-push image to ECR  (run before first apply)
#   (cd infra && terraform apply)
#   make deploy           # point the Lambda at the freshly pushed image
#
# Subsequent code changes:  make build → make push-ecr → make deploy
#
# Override any variable on the command line, e.g. `make push-ecr IMAGE_TAG=v2`.

PROJECT_NAME ?= filipino-sentiment
AWS_REGION   ?= ap-southeast-1
IMAGE_TAG    ?= latest
LOCAL_IMAGE  ?= $(PROJECT_NAME):$(IMAGE_TAG)
TEST_PORT    ?= 9000

# Resolved from the live AWS account/ECR repo (no hardcoded account id).
ACCOUNT_ID  = $(shell aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY = $(ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_REPO     = $(ECR_REGISTRY)/$(PROJECT_NAME)
REMOTE_IMAGE = $(ECR_REPO):$(IMAGE_TAG)

.PHONY: test build docker-run ecr-login push-ecr deploy logs url destroy clean

## Image -------------------------------------------------------------------

build:  ## Build the Lambda container image for linux/amd64
	docker build --platform linux/amd64 -t $(LOCAL_IMAGE) .

docker-run:  ## Run the image locally (maps container 8080 -> host 9000)
	docker run --rm -p 9000:8080 $(LOCAL_IMAGE)

test:  ## Smoke-test a running API (defaults to the container on :9000)
	python scripts/smoke_test.py http://localhost:$(TEST_PORT)

ecr-login:  ## Authenticate Docker to this account's ECR registry
	aws ecr get-login-password --region $(AWS_REGION) \
	  | docker login --username AWS --password-stdin $(ECR_REGISTRY)

push-ecr: ecr-login  ## Tag the local image and push it to ECR
	docker tag $(LOCAL_IMAGE) $(REMOTE_IMAGE)
	docker push $(REMOTE_IMAGE)
	@echo "Pushed $(REMOTE_IMAGE)"

## Deploy ------------------------------------------------------------------

deploy:  ## Point the Lambda at the latest pushed image and wait for rollout
	aws lambda update-function-code \
	  --function-name $(PROJECT_NAME) \
	  --image-uri $(REMOTE_IMAGE) \
	  --region $(AWS_REGION) >/dev/null
	aws lambda wait function-updated \
	  --function-name $(PROJECT_NAME) --region $(AWS_REGION)
	@echo "Deployed $(REMOTE_IMAGE) to function $(PROJECT_NAME)"

url:  ## Print the Function URL (from terraform output)
	@cd infra && terraform output -raw function_url

logs:  ## Tail the Lambda's CloudWatch logs
	aws logs tail /aws/lambda/$(PROJECT_NAME) --follow --region $(AWS_REGION)

destroy:  ## Tear down ALL AWS resources (Lambda, URL, ECR, IAM, logs)
	cd infra && terraform destroy

clean:  ## Remove the local image
	-docker rmi $(LOCAL_IMAGE)
