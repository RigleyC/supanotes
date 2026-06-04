// Package migrate runs golang-migrate migrations against the
// configured database. Migrations live in backend/db/migrations.
package migrate

import (
	"errors"
	"fmt"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/rs/zerolog/log"
)

// Up applies every pending migration in `path` (defaults to db/migrations)
// against `databaseURL`. Empty URL is a no-op so the server can start
// without a database in early-dev mode.
func Up(databaseURL, path string) error {
	if databaseURL == "" {
		log.Warn().Msg("migrate: DATABASE_URL empty, skipping migrations")
		return nil
	}
	if path == "" {
		path = "db/migrations"
	}

	src := "file://" + path
	m, err := migrate.New(src, databaseURL)
	if err != nil {
		return fmt.Errorf("migrate: open: %w", err)
	}
	defer m.Close()

	before, _, _ := m.Version()

	if err := m.Up(); err != nil {
		if errors.Is(err, migrate.ErrNoChange) {
			log.Info().Uint("version", before).Msg("migrate: schema up to date")
			return nil
		}
		return fmt.Errorf("migrate: up: %w", err)
	}

	after, _, _ := m.Version()
	log.Info().
		Uint("from", before).
		Uint("to", after).
		Msg("migrate: schema migrated")
	return nil
}
