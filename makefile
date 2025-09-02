# -------- Config (override via env or .env) --------
include .env
export

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

# -------- ECR push --------
.PHONY: ecr-login
ecr-login:
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com

.PHONY: ecr-create
ecr-create:
	aws ecr create-repository --repository-name $(ECR_REPO) --region $(AWS_REGION) || true

.PHONY: tag
tag:
	docker tag $(ECR_REPO):$(IMAGE_TAG) $(IMAGE_URI)

.PHONY: push
push: ecr-login ecr-create tag
	docker push $(IMAGE_URI)

# -------- Lambda deploy/update --------
# NOTE: Provide a valid IAM role ARN with AWSLambdaBasicExecutionRole attached.
.PHONY: deploy
deploy:
	aws lambda create-function \
	  --function-name $(FUNCTION_NAME) \
	  --package-type Image \
	  --code ImageUri=$(IMAGE_URI) \
	  --role $(LAMBDA_ROLE_ARN) \
	  --architectures $$( [ "$(ARCH)" = "arm64" ] && echo "arm64" || echo "x86_64" ) \
	  --region $(AWS_REGION)

.PHONY: update
update:
	aws lambda update-function-code \
	  --function-name $(FUNCTION_NAME) \
	  --image-uri $(IMAGE_URI) \
	  --publish \
	  --region $(AWS_REGION)

.PHONY: invoke-aws
invoke-aws:
	aws lambda invoke --function-name $(FUNCTION_NAME) --region $(AWS_REGION) response.json && cat response.json && echo
	
.PHONY: clean-aws
clean-aws:
	@echo "⚠️  This will delete the Lambda function '$(FUNCTION_NAME)' and ECR repo '$(ECR_REPO)' in region $(AWS_REGION)"
	@read -p "Are you sure? [y/N] " ans && [ "$$ans" = "y" ] || exit 1
	aws lambda delete-function \
	  --function-name $(FUNCTION_NAME) \
	  --region $(AWS_REGION) || true
	aws ecr delete-repository \
	  --repository-name $(ECR_REPO) \
	  --region $(AWS_REGION) \
	  --force || true
	@echo "✅ Cleanup complete."
	
.PHONY: logs
logs:
	@aws logs describe-log-streams \
	  --log-group-name /aws/lambda/lambda-anomaly-detector \
	  --order-by LastEventTime --descending --limit 1 \
	  --region us-west-2 \
	  --query 'logStreams[0].logStreamName' --output text | \
	xargs -I {} aws logs get-log-events \
	  --log-group-name /aws/lambda/lambda-anomaly-detector \
	  --log-stream-name "{}" \
	  --region us-west-2 \
	  --limit 100 --start-from-head \
	  --query 'events[].message' --output text


.PHONY: logs-event
logs-event:
	@LG="/aws/lambda/$(FUNCTION_NAME)"; \
	LS="$$(aws logs describe-log-streams \
	  --log-group-name "$$LG" \
	  --order-by LastEventTime --descending --limit 1 \
	  --region "$(AWS_REGION)" \
	  --query 'logStreams[0].logStreamName' --output text)"; \
	echo "Log group: $$LG"; \
	echo "Latest stream: $$LS"; \
	aws logs get-log-events \
	  --log-group-name "$$LG" \
	  --log-stream-name "$$LS" \
	  --region "$(AWS_REGION)" \
	  --limit 100 --start-from-head \
	  --query 'events[].message' --output text | sed 's/\\n/\n/g'