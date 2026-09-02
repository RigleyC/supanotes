package syncfeed

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/pkg/migrate"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func TestChangeFeedTriggersAndCursorWithPostgres(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_SYNC_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_SYNC_TEST_DATABASE_URL is not configured")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(
		filepath.Join(filepath.Dir(currentFile), "../../db/migrations"),
	)
	require.NoError(t, migrate.Up(databaseURL, migrationPath))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool.Close()

	ownerID := uuid.NewString()
	collaboratorID := uuid.NewString()
	noteID := uuid.NewString()
	defer func() {
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = ANY($1::uuid[])", []string{ownerID, collaboratorID})
	}()

	_, err = pool.Exec(ctx, `
		INSERT INTO users(id, email, password_hash, name)
		VALUES ($1, $2, 'hash', 'Owner'), ($3, $4, 'hash', 'Collaborator')
	`, ownerID, "owner-"+ownerID+"@example.com", collaboratorID, "collab-"+collaboratorID+"@example.com")
	require.NoError(t, err)

	_, err = pool.Exec(ctx, `
		INSERT INTO notes(id, user_id, content)
		VALUES ($1, $2, 'before')
	`, noteID, ownerID)
	require.NoError(t, err)

	_, err = pool.Exec(ctx, `
		INSERT INTO note_shares(note_id, user_id, permission)
		VALUES ($1, $2, 'edit')
	`, noteID, collaboratorID)
	require.NoError(t, err)

	_, err = pool.Exec(ctx, `
		UPDATE notes SET content = 'after', revision = 7, updated_at = NOW()
		WHERE id = $1
	`, noteID)
	require.NoError(t, err)

	_, err = pool.Exec(ctx, `
		INSERT INTO user_note_preferences(
			user_id, note_id, favorite, archived, hide_completed, collapse_images
		) VALUES ($1, $2, TRUE, FALSE, TRUE, FALSE)
		ON CONFLICT (user_id, note_id) DO UPDATE SET
			favorite = EXCLUDED.favorite,
			updated_at = NOW()
	`, collaboratorID, noteID)
	require.NoError(t, err)

	_, err = pool.Exec(ctx, `DELETE FROM note_shares WHERE note_id = $1 AND user_id = $2`, noteID, collaboratorID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `UPDATE notes SET deleted_at = NOW() WHERE id = $1`, noteID)
	require.NoError(t, err)

	ownerKinds := loadKinds(t, ctx, pool, ownerID, noteID)
	require.Subset(t, ownerKinds, []string{"note_changed", "note_deleted"})
	require.Equal(t, "note_changed", ownerKinds[0])
	require.Equal(t, "note_deleted", ownerKinds[len(ownerKinds)-1])

	collaboratorKinds := loadKinds(t, ctx, pool, collaboratorID, noteID)
	require.Equal(t, []string{
		"note_access_changed",
		"note_changed",
		"note_preferences_changed",
		"note_access_revoked",
	}, collaboratorKinds)

	var revision int64
	err = pool.QueryRow(ctx, `
		SELECT revision
		FROM sync_changes
		WHERE target_user_id = $1 AND note_id = $2 AND kind = 'note_changed'
		ORDER BY sequence DESC
		LIMIT 1
	`, collaboratorID, noteID).Scan(&revision)
	require.NoError(t, err)
	require.EqualValues(t, 7, revision)

	collaboratorUUID, err := uid.UUIDFromString(collaboratorID)
	require.NoError(t, err)
	page, err := NewRepository(pool).ListChanges(ctx, collaboratorUUID, 0, 2)
	require.NoError(t, err)
	require.Len(t, page.Changes, 2)
	require.True(t, page.HasMore)
	require.GreaterOrEqual(t, page.Watermark, page.Cursor)
	require.Equal(t, collaboratorID, collaboratorUUID.String())
}

func loadKinds(
	t *testing.T,
	ctx context.Context,
	pool *pgxpool.Pool,
	userID string,
	noteID string,
) []string {
	t.Helper()
	rows, err := pool.Query(ctx, `
		SELECT kind
		FROM sync_changes
		WHERE target_user_id = $1 AND note_id = $2
		ORDER BY sequence ASC
	`, userID, noteID)
	require.NoError(t, err)
	defer rows.Close()

	var kinds []string
	for rows.Next() {
		var kind string
		require.NoError(t, rows.Scan(&kind))
		kinds = append(kinds, kind)
	}
	require.NoError(t, rows.Err())
	return kinds
}
