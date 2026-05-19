IMAGE_NAME := psyb0t/pibox
BASE_IMAGE := aicodebox-base
BASE_DIR   := ../docker-aicodebox
TAG        := local

.PHONY: all build build-base test clean help

all: build ## Build the pibox image (builds base first)

build-base: ## Build aicodebox-base from the sibling repo
	@if [ ! -d "$(BASE_DIR)" ]; then \
		echo "❌ base repo not found at $(BASE_DIR) — clone psyb0t/docker-aicodebox next to this repo"; \
		exit 1; \
	fi
	docker build -t $(BASE_IMAGE):$(TAG) $(BASE_DIR)

build: build-base ## Build the pibox image
	docker build --build-arg BASE_IMAGE=$(BASE_IMAGE):$(TAG) -t $(IMAGE_NAME):$(TAG) .

test: ## Run the full e2e test suite (needs .env.test)
	bash test.sh

clean: ## Remove built images
	docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null || true
	docker rmi $(BASE_IMAGE):$(TAG) 2>/dev/null || true

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
