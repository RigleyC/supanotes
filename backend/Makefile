.PHONY: help run build test lint tidy migrate-up migrate-down migrate-create sqlc dev-db-up dev-db-down

GO ?= go
MIGRATE ?= migrate
DATABASE_URL ?= postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable

help:
	@echo "SupaNotes backend — available targets:"
	@echo "  run             - run the API server ($$PORT or 8080)"
	@echo "  build           - compile binary into bin/server"
	@echo "  test            - run go test ./..."
	@echo "  lint            - run go vet ./..."
	@echo "  tidy            - run go mod tidy"
	@echo "  migrate-up      - apply all pending DB migrations"
	@echo "  migrate-down    - roll back the last DB migration"
	@echo "  migrate-create  - create a new migration: make migrate-create name=foo"
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
	$(MIGRATE) -path db/migrations -database "$(DATABASE_URL)" up

migrate-down:
	$(MIGRATE) -path db/migrations -database "$(DATABASE_URL)" down 1

migrate-create:
	@test -n "$(name)" || (echo "usage: make migrate-create name=foo" && exit 1)
	$(MIGRATE) create -ext sql -dir db/migrations -seq $(name)

sqlc:
	sqlc generate

dev-db-up:
	docker compose up -d postgres

dev-db-down:
	docker compose down
