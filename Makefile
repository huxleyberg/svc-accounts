OUTPUT = main # will be archived
PACKAGED_TEMPLATE = packaged.yaml # will be archived
TEMPLATE = template.yaml
VERSION = 0.1
S3_BUCKET := lambda-resources-huxleyberg
ZIPFILE = lambda.zip
OUTPUT_CONSUMER = main-consumer-lambda # will be archived
SERVICE_NAME = svc-accounts

.PHONY: ci
ci: install lint test

.PHONY: test
test:
	go test ./...

.PHONY: clean
clean:
	rm -f $(OUTPUT)
	rm -f $(OUTPUT_CONSUMER)
	rm -f $(ZIPFILE)

.PHONY: install
install:
	go get -t ./...
	# go get -u honnef.co/go/tools/cmd/megacheck
	go get golang.org/x/lint/golint

local-install:
	go get -u github.com/awslabs/aws-sam-local

.PHONY: lint
lint: install
	# megacheck -go $(VERSION)
	golint -set_exit_status

main: ./cmd/$(SERVICE_NAME)-lambda/main.go
	go build -o $(OUTPUT) ./cmd/$(SERVICE_NAME)-publisher-lambda/main.go
	go build -o $(OUTPUT_CONSUMER) ./cmd/$(SERVICE_NAME)-consumer-lambda/main.go

# compile the code to run in Lambda (local or real)
.PHONY: lambda
lambda:
	GOOS=linux GOARCH=amd64 $(MAKE) main

# create a lambda deployment package
$(ZIPFILE): clean lambda
	zip -9 -r $(ZIPFILE) $(OUTPUT)

.PHONY: run-local
local-deploy: local-install
	aws-sam-local local start-api

.PHONY: build
build: clean lambda

# TODO: Encrypt package in S3 with --kms-key-id
.PHONY: package
package:
	aws s3 cp open-api-integrated.yaml s3://$(S3_BUCKET)/open-api/$(SERVICE_NAME)/open-api-integrated.yaml
	aws cloudformation package --template-file $(TEMPLATE) --s3-bucket $(S3_BUCKET) --output-template-file $(PACKAGED_TEMPLATE)

build-local:
	go build -o $(OUTPUT) ./cmd/$(SERVICE_NAME)/main.go

deploy-local: build
	sls deploy -c ./serverless-infra.yml --stage local --verbose
	sls deploy --stage local --verbose

run: build-local
	@echo ">> Running application ..."
	PORT=7565 \
	MONGO=mongodb://localhost:27017 \
	AWS_REGION=us-east-1 \
	./$(OUTPUT)