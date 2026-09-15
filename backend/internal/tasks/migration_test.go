package tasks

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

func TestTaskMigration(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_SYNC_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_SYNC_TEST_DATABASE_URL is not configured; PostgreSQL migration not exercised")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(filepath.Join(filepath.Dir(currentFile), "../../db/migrations"))
	require.NoError(t, applyMigrations(databaseURL, migrationPath))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool.Close()

	for _, column := range []string{"owner_user_id", "completions", "schedule_generation", "deleted_at"} {
		var exists bool
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM information_schema.columns
				WHERE table_schema = current_schema() AND table_name = 'tasks' AND column_name = $1
			)`, column).Scan(&exists))
		require.True(t, exists, "tasks.%s must be present", column)
	}

	for _, column := range []string{"operation_id", "payload_hash", "response_json"} {
		var exists bool
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM information_schema.columns
				WHERE table_schema = current_schema() AND table_name = 'task_operations' AND column_name = $1
			)`, column).Scan(&exists))
		require.True(t, exists, "task_operations.%s must be present", column)
	}

	for _, table := range []string{"tasks_legacy_quarantine_v31", "task_completions_legacy_quarantine_v31"} {
		var exists bool
		require.NoError(t, pool.QueryRow(ctx, `
			SELECT to_regclass(current_schema() || '.' || $1) IS NOT NULL`, table).Scan(&exists))
		require.True(t, exists, "%s must be retained as quarantine", table)
	}

	var taskIDExists bool
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM information_schema.columns
			WHERE table_schema = current_schema() AND table_name = 'sync_changes' AND column_name = 'task_id'
		)`).Scan(&taskIDExists))
	require.True(t, taskIDExists)
}

func applyMigrations(databaseURL, migrationPath string) error {
	m, err := migrate.New("file://"+migrationPath, databaseURL)
	if err != nil {
		return err
	}
	defer m.Close()
	return m.Up()
}
