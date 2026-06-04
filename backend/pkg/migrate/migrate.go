// Package migrate hosts programmatic schema migrations.
//
// Feature 0 — Foundation: the runner is not yet wired into main.go.
// Migrations are run from the Makefile via the `migrate` CLI (see
// `make migrate-up` / `make migrate-down`). The blank imports below
// pin the postgres + file drivers in go.mod so future features that
// switch to programmatic migrations (e.g., embedding into a startup
// hook) can pick them up without re-resolving the module graph.
package migrate

import (
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)
