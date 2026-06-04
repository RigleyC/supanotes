// Package db owns the PostgreSQL connection pool and exposes
// helpers to obtain a configured *pgxpool.Pool.
//
// Feature 0 — Foundation: the connection is not yet wired into main.go
// (this lands with the auth and notes features). The blank import below
// pins the dependency in go.mod so future features can pick it up
// without re-resolving the module graph.
package db

import (
	_ "github.com/jackc/pgx/v5/pgxpool"
)
