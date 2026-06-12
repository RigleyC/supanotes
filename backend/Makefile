.PHONY: help run build test lint tidy migrate-up sqlc dev-db-up dev-db-down

GO ?= go

help:
	@echo "SupaNotes backend - available targets:"
	@echo "  run             - run the API server (PORT env, default 8080)"
	@echo "  build           - compile binary into bin/server"
	@echo "  test            - run go test ./..."
	@echo "  lint            - run go vet ./..."
	@echo "  tidy            - run go mod tidy"
	@echo "  migrate-up      - apply all pending DB migrations"
	@echo "  sqlc            - regenerate typed Go from db/queries (requires sqlc)"
	@echo "  dev-db-up       - start the local Postgres container"
	@echo "  dev-db-down     - stop the local Postgres container"

run:
	$(GO) run ./cmd/server

build:
	$(GO) build -o bin/server ./cmd/server

test:
	$(GO) test ./...

lint:
	$(GO) vet ./...

tidy:
	$(GO) mod tidy

migrate-up:
	$(GO) run ./cmd/migrate

sqlc:
	sqlc generate

dev-db-up:
	docker compose up -d postgres

dev-db-down:
	docker compose down
