package attachments

import (
	"context"
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

func TestAttachmentDeletionOutboxMigration(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_ATTACHMENT_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_ATTACHMENT_TEST_DATABASE_URL is not configured; PostgreSQL migration not exercised")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(filepath.Join(filepath.Dir(currentFile), "../../db/migrations"))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	admin, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	schema := fmt.Sprintf("attachment_migration_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE SCHEMA "+schema)
	require.NoError(t, err)
	defer func() {
		_, _ = admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
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
	require.NoError(t, m.Migrate(55))
	require.NoError(t, m.Up())

	pool, err := pgxpool.New(ctx, schemaURL)
	require.NoError(t, err)
	defer pool.Close()

	ownerID := "11111111-1111-4111-8111-111111111111"
	noteID := "22222222-2222-4222-8222-222222222222"
	attachmentA := "33333333-3333-4333-8333-333333333333"
	attachmentB := "44444444-4444-4444-8444-444444444444"
	sharedKey := "attachments/migration/shared.bin"

	_, err = pool.Exec(ctx, `INSERT INTO users(id, email, password_hash, name) VALUES ($1, 'attachment-migration@example.com', 'hash', 'Migration owner')`, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO notes(id, user_id, content) VALUES ($1, $2, 'attachment migration')`, noteID, ownerID)
	require.NoError(t, err)
	for _, id := range []string{attachmentA, attachmentB} {
		_, err = pool.Exec(ctx, `INSERT INTO attachments(id, note_id, filename, storage_key, mime_type, size_bytes) VALUES ($1, $2, 'shared.bin', $3, 'application/octet-stream', 1)`, id, noteID, sharedKey)
		require.NoError(t, err)
	}

	_, err = pool.Exec(ctx, `DELETE FROM attachments WHERE id = $1`, attachmentA)
	require.NoError(t, err)
	var outboxCount int
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM attachment_deletion_outbox WHERE storage_key = $1`, sharedKey).Scan(&outboxCount))
	require.Zero(t, outboxCount, "a shared object must not be queued while another reference exists")

	_, err = pool.Exec(ctx, `DELETE FROM attachments WHERE id = $1`, attachmentB)
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM attachment_deletion_outbox WHERE storage_key = $1`, sharedKey).Scan(&outboxCount))
	require.Equal(t, 1, outboxCount)

	var claimedKey string
	var referenced bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT storage_key, referenced FROM claim_attachment_storage_deletion($1)`, sharedKey).Scan(&claimedKey, &referenced))
	require.Equal(t, sharedKey, claimedKey)
	require.False(t, referenced)
	_, err = pool.Exec(ctx, `DELETE FROM attachment_deletion_outbox WHERE storage_key = $1`, sharedKey)
	require.NoError(t, err)

	hardDeleteNoteID := "55555555-5555-4555-8555-555555555555"
	hardDeleteKey := "attachments/migration/hard-delete.bin"
	_, err = pool.Exec(ctx, `INSERT INTO notes(id, user_id, content, deleted_at) VALUES ($1, $2, 'deleted', NOW() - INTERVAL '31 days')`, hardDeleteNoteID, ownerID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO attachments(note_id, filename, storage_key, mime_type, size_bytes) VALUES ($1, 'hard-delete.bin', $2, 'application/octet-stream', 1)`, hardDeleteNoteID, hardDeleteKey)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `DELETE FROM notes WHERE deleted_at < NOW() - INTERVAL '30 days'`)
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM attachment_deletion_outbox WHERE storage_key = $1`, hardDeleteKey).Scan(&outboxCount))
	require.Equal(t, 1, outboxCount, "hard-delete cascade must leave a durable cleanup intent")
}
