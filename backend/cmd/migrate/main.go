package main

import (
	"os"

	"github.com/rs/zerolog/log"

	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/migrate"
)

const defaultDatabaseURL = "postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable"

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal().Err(err).Msg("failed to load config")
	}
	if cfg.DatabaseURL == "" {
		cfg.DatabaseURL = defaultDatabaseURL
	}

	path := os.Getenv("MIGRATIONS_PATH")
	if path == "" {
		path = "db/migrations"
	}

	if err := migrate.Up(cfg.DatabaseURL, path); err != nil {
		log.Fatal().Err(err).Msg("migrations failed")
	}
}
