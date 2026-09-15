package tasks

import (
	"context"
	"errors"
	"fmt"
	"net/url"
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
	for _, scenario := range []struct {
		name  string
		guard func(context.Context, *pgxpool.Pool, string)
	}{
		{name: "task", guard: func(ctx context.Context, pool *pgxpool.Pool, ownerID string) {
			_, err := pool.Exec(ctx, `INSERT INTO tasks(id, owner_user_id, title) VALUES ('44444444-4444-4444-8444-444444444444', $1, 'new task')`, ownerID)
			require.NoError(t, err)
		}},
		{name: "operation", guard: func(ctx context.Context, pool *pgxpool.Pool, ownerID string) {
			_, err := pool.Exec(ctx, `INSERT INTO tasks(id, owner_user_id, title) VALUES ('44444444-4444-4444-8444-444444444444', $1, 'new task')`, ownerID)
			require.NoError(t, err)
			_, err = pool.Exec(ctx, `INSERT INTO task_operations(task_id, operation_id, payload_hash, response_json) VALUES ('44444444-4444-4444-8444-444444444444', '55555555-5555-4555-8555-555555555555', 'hash', '{}'::jsonb)`)
			require.NoError(t, err)
		}},
		{name: "feed event", guard: func(ctx context.Context, pool *pgxpool.Pool, ownerID string) {
			_, err := pool.Exec(ctx, `INSERT INTO sync_changes(target_user_id, kind, task_id) VALUES ($1, 'task_changed', '44444444-4444-4444-8444-444444444444')`, ownerID)
			require.NoError(t, err)
		}},
	} {
		t.Run(scenario.name+" rollback guard", func(t *testing.T) {
			runTaskMigrationScenario(t, databaseURL, migrationPath, scenario.name, scenario.guard, false)
		})
	}
	t.Run("empty rollback restores legacy rows", func(t *testing.T) {
		runTaskMigrationScenario(t, databaseURL, migrationPath, "", nil, true)
	})
}

func runTaskMigrationScenario(t *testing.T, databaseURL, migrationPath, guardLabel string, guard func(context.Context, *pgxpool.Pool, string), expectDown bool) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	admin, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	schema := fmt.Sprintf("task_migration_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, `CREATE SCHEMA `+schema)
	require.NoError(t, err)
	defer func() {
		_, _ = admin.Exec(ctx, `DROP SCHEMA `+schema+` CASCADE`)
		admin.Close()
	}()

	parsed, err := url.Parse(databaseURL)
	require.NoError(t, err)
	query := parsed.Query()
	query.Set("search_path", schema+",public")
	parsed.RawQuery = query.Encode()
	schemaURL := parsed.String()
	m, err := migrate.New("file://"+migrationPath, schemaURL)
	require.NoError(t, err)
	defer m.Close()
	require.NoError(t, m.Migrate(54))
	pool, err := pgxpool.New(ctx, schemaURL)
	require.NoError(t, err)
	defer pool.Close()

	ownerID := "11111111-1111-4111-8111-111111111111"
	noteID := "22222222-2222-4222-8222-222222222222"
	legacyTaskID := "33333333-3333-4333-8333-333333333333"
	_, err = pool.Exec(ctx, `INSERT INTO users(id, email, password_hash, name) VALUES ($1, 'migration-task-owner@example.com', 'hash', 'Migration owner')`, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO notes(id, user_id, content) VALUES ($1, $2, 'legacy')`, noteID, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO tasks(id, note_id, user_id, title, status) VALUES ($1, $2, $3, 'legacy task', 'open')`, legacyTaskID, noteID, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO task_completions(task_id, completed_at, due_date, scheduled_at) VALUES ($1, '2026-09-15T12:00:00Z', '2026-09-15', '2026-09-15T09:00:00Z')`, legacyTaskID)
	require.NoError(t, err)
	require.NoError(t, m.Up())

	var count int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks_legacy_quarantine_v31 WHERE id = $1`, legacyTaskID).Scan(&count))
	require.Equal(t, 1, count)
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM task_completions_legacy_quarantine_v31 WHERE task_id = $1`, legacyTaskID).Scan(&count))
	require.Equal(t, 1, count)
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks WHERE id = $1`, legacyTaskID).Scan(&count))
	require.Zero(t, count)

	if guard != nil {
		guard(ctx, pool, ownerID)
		downErr := m.Steps(-1)
		require.Error(t, downErr)
		require.Contains(t, downErr.Error(), guardLabel)
		_, dirty, versionErr := m.Version()
		require.NoError(t, versionErr)
		require.True(t, dirty, "golang-migrate marks a failed down migration dirty")
		require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks_legacy_quarantine_v31 WHERE id = $1`, legacyTaskID).Scan(&count))
		require.Equal(t, 1, count)
		var taskColumnExists bool
		require.NoError(t, pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'sync_changes' AND column_name = 'task_id')`).Scan(&taskColumnExists))
		require.True(t, taskColumnExists)
		return
	}

	require.True(t, expectDown)
	require.NoError(t, m.Steps(-1))
	var restoredTitle, restoredStatus string
	require.NoError(t, pool.QueryRow(ctx, `SELECT title, status FROM tasks WHERE id = $1`, legacyTaskID).Scan(&restoredTitle, &restoredStatus))
	require.Equal(t, "legacy task", restoredTitle)
	require.Equal(t, "open", restoredStatus)
	var completedAt, scheduledAt time.Time
	var dueDate time.Time
	require.NoError(t, pool.QueryRow(ctx, `SELECT completed_at, due_date, scheduled_at FROM task_completions WHERE task_id = $1`, legacyTaskID).Scan(&completedAt, &dueDate, &scheduledAt))
	require.Equal(t, time.Date(2026, time.September, 15, 12, 0, 0, 0, time.UTC), completedAt.UTC())
	require.Equal(t, time.Date(2026, time.September, 15, 0, 0, 0, 0, time.UTC), dueDate.UTC())
	require.Equal(t, time.Date(2026, time.September, 15, 9, 0, 0, 0, time.UTC), scheduledAt.UTC())
	var restoredCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM tasks WHERE id = $1`, legacyTaskID).Scan(&restoredCount))
	require.Equal(t, 1, restoredCount)
	var taskColumnExists bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'sync_changes' AND column_name = 'task_id')`).Scan(&taskColumnExists))
	require.False(t, taskColumnExists)
}
