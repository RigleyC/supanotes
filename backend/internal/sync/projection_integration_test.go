//go:build integration

package sync

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestProjectNoteContentOrphanedTasks(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)

	noteID := uuid.New().String()
	noteUUID, err := uuid.Parse(noteID)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW()) ON CONFLICT (id) DO NOTHING`, noteID)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM task_completions WHERE task_id IN (SELECT id FROM tasks WHERE note_id = $1)", noteID)
		pool.Exec(ctx, "DELETE FROM tasks WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	taskID := uuid.New().String()

	// Step 1: Create YDoc with one task node, project it
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	doc.Transact(func(txn *crdt.Transaction) {
		meta, _ := json.Marshal(map[string]interface{}{
			"id":       taskID,
			"type":     "task",
			"position": "a0",
			"data":     json.RawMessage(`{"text":"a task"}`),
		})
		nodesMap.Set(txn, taskID, string(meta))
	})
	state := crdt.EncodeStateAsUpdateV1(doc, nil)
	_, err = pool.Exec(ctx, "INSERT INTO note_yjs_states (note_id, state) VALUES ($1, $2)", noteID, state)
	require.NoError(t, err)

	err = ProjectNoteContentFromYDoc(ctx, pool, noteID)
	require.NoError(t, err)

	var taskCount int
	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM tasks WHERE note_id = $1 AND deleted_at IS NULL", noteUUID).Scan(&taskCount)
	require.NoError(t, err)
	assert.Equal(t, 1, taskCount, "task should exist after first projection")

	// Step 2: Create a task_completion for the task
	q := sqlcgen.New(pool)
	_, err = q.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
		ID:          pgtype.UUID{Bytes: uuid.New(), Valid: true},
		TaskID:      pgtype.UUID{Bytes: taskUUID(t, taskID), Valid: true},
		CompletedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
		UserID:      pgtype.UUID{Bytes: uuid.MustParse("00000000-0000-0000-0000-000000000000"), Valid: true},
	})
	require.NoError(t, err)

	var completionCount int
	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM task_completions WHERE task_id = $1", taskID).Scan(&completionCount)
	require.NoError(t, err)
	assert.Equal(t, 1, completionCount, "should have 1 task_completion")

	// Step 3: Remove the task node from YDoc, re-project
	doc2 := crdt.New(crdt.WithGC(false))
	err = crdt.ApplyUpdateV1(doc2, state, nil)
	require.NoError(t, err)
	nodesMap = doc2.GetMap("nodes")
	doc2.Transact(func(txn *crdt.Transaction) {
		nodesMap.Delete(txn, taskID)
	})
	newState := crdt.EncodeStateAsUpdateV1(doc2, nil)
	_, err = pool.Exec(ctx, "UPDATE note_yjs_states SET state = $1 WHERE note_id = $2", newState, noteID)
	require.NoError(t, err)

	err = ProjectNoteContentFromYDoc(ctx, pool, noteID)
	require.NoError(t, err)

	// Step 4: Verify task is soft-deleted, task_completions preserved
	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM tasks WHERE note_id = $1 AND deleted_at IS NULL", noteUUID).Scan(&taskCount)
	require.NoError(t, err)
	assert.Equal(t, 0, taskCount, "task should be soft-deleted after removal from YDoc")

	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM task_completions WHERE task_id = $1", taskID).Scan(&completionCount)
	require.NoError(t, err)
	assert.Equal(t, 1, completionCount, "task_completions should be preserved after task deletion")
}

func taskUUID(t *testing.T, s string) [16]byte {
	t.Helper()
	u, err := uuid.Parse(s)
	require.NoError(t, err)
	return u
}
