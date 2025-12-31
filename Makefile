.PHONY: help build test examples clean format generator

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the library (syntax check)
	@echo "Checking Crystal syntax..."
	@crystal build --no-codegen src/crystal-grpc.cr

generator: ## Build the code generator
	@echo "Building code generator..."
	@mkdir -p bin
	@crystal build bin/protoc-gen-crystal -o bin/protoc-gen-crystal
	@echo "Generator built: bin/protoc-gen-crystal"

test: ## Run tests
	@echo "Running tests..."
	@crystal spec

examples: ## Build examples
	@echo "Building echo server..."
	@mkdir -p bin
	@crystal build examples/echo_server.cr -o bin/echo_server
	@echo "Building echo client..."
	@crystal build examples/echo_client.cr -o bin/echo_client
	@echo "Examples built in bin/"

run-server: ## Run the echo server example
	@crystal run examples/echo_server.cr

run-client: ## Run the echo client example
	@crystal run examples/echo_client.cr

clean: ## Clean build artifacts
	@rm -rf bin/
	@rm -rf lib/
	@rm -rf .shards/
	@echo "Cleaned build artifacts"

format: ## Format code (if crystal format is available)
	@crystal tool format src/ spec/ examples/

install: ## Install dependencies
	@shards install

.DEFAULT_GOAL := help
