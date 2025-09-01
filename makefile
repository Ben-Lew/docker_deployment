# -------- Config (override via env or .env) --------
include .env
export

# If you don't use .env, you can set vars in your shell:
# export AWS_ACCOUNT_ID=111122223333
# export AWS_REGION=us-west-2
# export ECR_REPO=lambda-anomaly-detector
# export FUNCTION_NAME=lambda-anomaly-detector
# export ARCH=amd64  # or arm64

IMAGE_TAG ?= latest
IMAGE_URI  := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO):$(IMAGE_TAG)
PLATFORM   ?= linux/$(ARCH)

# -------- Local build & run --------
.PHONY: build
build:
	docker buildx build --platform $(PLATFORM) -t $(ECR_REPO):$(IMAGE_TAG) --provenance=false .

.PHONY: run
run:
	docker run --platform $(PLATFORM) -p 9000:8080 $(ECR_REPO):$(IMAGE_TAG)

.PHONY: invoke
invoke:
	curl -s "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{"ping":"pong"}' | jq .

.PHONY: stop
stop:
	docker ps --filter "ancestor=$(ECR_REPO):$(IMAGE_TAG)" --format "{{.ID}}" | xargs -I {} docker kill {}

# # -------- ECR push --------
# .PHONY: ecr-login
# ecr-login:
# \taws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
#
# .PHONY: ecr-create
# ecr-create:
# \taws ecr create-repository --repository-name $(ECR_REPO) --region $(AWS_REGION) || true
#
# .PHONY: tag
# tag:
# \tdocker tag $(ECR_REPO):$(IMAGE_TAG) $(IMAGE_URI)
#
# .PHONY: push
# push: ecr-login ecr-create tag
# \tdocker push $(IMAGE_URI)
#
# # -------- Lambda deploy/update --------
# # NOTE: Provide a valid IAM role ARN with AWSLambdaBasicExecutionRole attached.
# .PHONY: deploy
# deploy:
# \taws lambda create-function \\
# \t  --function-name $(FUNCTION_NAME) \\
# \t  --package-type Image \\
# \t  --code ImageUri=$(IMAGE_URI) \\
# \t  --role $(LAMBDA_ROLE_ARN) \\
# \t  --architectures $$( [ "$(ARCH)" = "arm64" ] && echo "arm64" || echo "x86_64" ) \\
# \t  --region $(AWS_REGION)
#
# .PHONY: update
# update:
# \taws lambda update-function-code \\
# \t  --function-name $(FUNCTION_NAME) \\
# \t  --image-uri $(IMAGE_URI) \\
# \t  --publish \\
# \t  --region $(AWS_REGION)
#
# .PHONY: invoke-aws
# invoke-aws:
# \taws lambda invoke --function-name $(FUNCTION_NAME) --region $(AWS_REGION) response.json && cat response.json && echo
