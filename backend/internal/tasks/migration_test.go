package tasks

import (
	"context"
	"errors"
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
	var dueDateType string
	require.NoError(t, pool.QueryRow(ctx, `
		SELECT data_type FROM information_schema.columns
		WHERE table_schema = current_schema() AND table_name = 'tasks' AND column_name = 'due_date'
	`).Scan(&dueDateType))
	require.Equal(t, "timestamp without time zone", dueDateType)

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
	err = m.Up()
	if errors.Is(err, migrate.ErrNoChange) {
		return nil
	}
	return err
}

// This test intentionally uses a separately provisioned database. It starts at
// version 54 so it can prove that legacy rows are retained instead of being
// promoted, then exercises every down-migration data guard.
func TestTaskMigrationQuarantineAndRollbackGuards(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL is not configured; isolated PostgreSQL migration test not exercised")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(filepath.Join(filepath.Dir(currentFile), "../../db/migrations"))
	m, err := migrate.New("file://"+migrationPath, databaseURL)
	require.NoError(t, err)
	defer m.Close()
	version, dirty, err := m.Version()
	require.NoError(t, err)
	if dirty || (version != 0 && version != 54) {
		t.Skipf("isolated migration database must be clean or at version 54 (version=%d dirty=%v)", version, dirty)
	}
	if version == 0 {
		require.NoError(t, m.Migrate(54))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool.Close()

	ownerID := "11111111-1111-4111-8111-111111111111"
	noteID := "22222222-2222-4222-8222-222222222222"
	legacyTaskID := "33333333-3333-4333-8333-333333333333"
	_, err = pool.Exec(ctx, `
		INSERT INTO users(id, email, password_hash, name)
		VALUES ($1, 'migration-task-owner@example.com', 'hash', 'Migration owner')
		ON CONFLICT (id) DO NOTHING`, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO notes(id, user_id, content) VALUES ($1, $2, 'legacy') ON CONFLICT (id) DO NOTHING`, noteID, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO tasks(id, note_id, user_id, title, status)
		VALUES ($1, $2, $3, 'legacy task', 'open')`, legacyTaskID, noteID, ownerID)
	require.NoError(t, err)

	require.NoError(t, m.Up())
	var quarantineCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks_legacy_quarantine_v31 WHERE id = $1`, legacyTaskID).Scan(&quarantineCount))
	require.Equal(t, 1, quarantineCount)
	var promotedCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks WHERE id = $1`, legacyTaskID).Scan(&promotedCount))
	require.Zero(t, promotedCount)

	newTaskID := "44444444-4444-4444-8444-444444444444"
	insertNewTask := func() {
		_, err = pool.Exec(ctx, `INSERT INTO tasks(id, owner_user_id, title) VALUES ($1, $2, 'new task')`, newTaskID, ownerID)
		require.NoError(t, err)
	}
	assertGuarded := func(label string) {
		t.Helper()
		err := m.Steps(-1)
		require.Error(t, err, label)
		currentVersion, currentDirty, versionErr := m.Version()
		require.NoError(t, versionErr)
		require.EqualValues(t, 55, currentVersion)
		require.False(t, currentDirty)
		var taskColumnExists bool
		require.NoError(t, pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sync_changes' AND column_name = 'task_id')`).Scan(&taskColumnExists))
		require.True(t, taskColumnExists)
	}

	insertNewTask()
	assertGuarded("task rows must guard down migration")
	_, err = pool.Exec(ctx, `DELETE FROM tasks WHERE id = $1`, newTaskID)
	require.NoError(t, err)
	insertNewTask()
	_, err = pool.Exec(ctx, `INSERT INTO task_operations(task_id, operation_id, payload_hash, response_json) VALUES ($1, '55555555-5555-4555-8555-555555555555', 'hash', '{}'::jsonb)`, newTaskID)
	require.NoError(t, err)
	assertGuarded("operation rows must guard down migration")
	_, err = pool.Exec(ctx, `DELETE FROM task_operations WHERE task_id = $1`, newTaskID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM tasks WHERE id = $1`, newTaskID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO sync_changes(target_user_id, kind, task_id) VALUES ($1, 'task_changed', $2)`, ownerID, newTaskID)
	require.NoError(t, err)
	assertGuarded("task feed events must guard down migration")
	_, err = pool.Exec(ctx, `DELETE FROM sync_changes WHERE task_id = $1`, newTaskID)
	require.NoError(t, err)

	require.NoError(t, m.Steps(-1))
	var restored bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT to_regclass(current_schema() || '.tasks') IS NOT NULL AND to_regclass(current_schema() || '.task_completions') IS NOT NULL`).Scan(&restored))
	require.True(t, restored)
	var taskColumnExists bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sync_changes' AND column_name = 'task_id')`).Scan(&taskColumnExists))
	require.False(t, taskColumnExists)
	_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, ownerID)
	require.NoError(t, m.Up())
}
