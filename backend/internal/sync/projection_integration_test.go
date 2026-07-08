//go:build integration

package sync

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)


func insertNote(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(context.Background(),
		`INSERT INTO notes (id, user_id) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING`,
		testNoteID, testNoteUserID)
	require.NoError(t, err)
}

func getNodeType(t *testing.T, pool *pgxpool.Pool, nodeID string) string {
	t.Helper()
	var typ string
	err := pool.QueryRow(context.Background(),
		`SELECT type FROM note_nodes WHERE id = $1`, nodeID).Scan(&typ)
	require.NoError(t, err)
	return typ
}

func makeNodeUpdate(t *testing.T, nodes map[string]string) []byte {
	t.Helper()
	doc := crdt.New(crdt.WithGC(false))
	m := doc.GetMap("nodes")
	doc.Transact(func(txn *crdt.Transaction) {
		for k, v := range nodes {
			m.Set(txn, k, v)
		}
	})
	return crdt.EncodeStateAsUpdateV1(doc, nil)
}

func projectUpdateHelper(ctx context.Context, pool *pgxpool.Pool, noteID string, update []byte) error {
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, update, nil); err != nil {
		return err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err := ProjectToDBTxFromDoc(ctx, tx, doc, noteID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func TestProjectToDB_InsertsNodes(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	nodeID := "00000000-0000-0000-0000-000000000010"
	nodeJSON := fmt.Sprintf(`{"id":"%s","parentId":"","position":0,"type":"text","data":{"text":"hello"}}`, nodeID)
	update := makeNodeUpdate(t, map[string]string{nodeID: nodeJSON})

	err := projectUpdateHelper(ctx, pool, testNoteID, update)
	require.NoError(t, err)
	assert.Equal(t, "text", getNodeType(t, pool, nodeID))
}

func TestProjectToDB_InsertsTasks(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	taskID := "00000000-0000-0000-0000-000000000020"
	taskJSONStr := fmt.Sprintf(`{"id":"%s","noteId":"%s","title":"Buy milk","status":"open","position":0}`, taskID, testNoteID)

	doc := crdt.New(crdt.WithGC(false))
	tasksMap := doc.GetMap("tasks")
	doc.Transact(func(txn *crdt.Transaction) {
		tasksMap.Set(txn, taskID, taskJSONStr)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	err := projectUpdateHelper(ctx, pool, testNoteID, update)
	require.NoError(t, err)

	var title, status string
	var noteID pgtype.UUID
	err = pool.QueryRow(ctx,
		`SELECT title, status, note_id FROM tasks WHERE id = $1`, taskID).Scan(&title, &status, &noteID)
	require.NoError(t, err)
	assert.Equal(t, "Buy milk", title)
	assert.Equal(t, "open", status)
	assert.Equal(t, testNoteID, uuid.UUID(noteID.Bytes).String())
}

func TestProjectToDB_UpdatesExistingNode(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	pgNoteID := pgtype.UUID{Bytes: uuid.MustParse(testNoteID), Valid: true}

	nodeID := "00000000-0000-0000-0000-000000000030"
	pgNodeID := pgtype.UUID{Bytes: uuid.MustParse(nodeID), Valid: true}
	q := sqlcgen.New(pool)
	q.UpsertNoteNode(ctx, sqlcgen.UpsertNoteNodeParams{
		ID:     pgNodeID,
		NoteID: pgNoteID,
		Type:   "text",
		Data:   []byte(`{"text":"initial"}`),
		DeletedAt: pgtype.Timestamptz{Valid: false},
	})

	updatedJSON := fmt.Sprintf(`{"id":"%s","parentId":"","position":1,"type":"heading","data":{"text":"updated"}}`, nodeID)
	update := makeNodeUpdate(t, map[string]string{nodeID: updatedJSON})

	err := projectUpdateHelper(ctx, pool, testNoteID, update)
	require.NoError(t, err)
	assert.Equal(t, "heading", getNodeType(t, pool, nodeID))
}

func TestReconstructYDocFromNodes_RoundTrip(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	pgNoteID := pgtype.UUID{Bytes: uuid.MustParse(testNoteID), Valid: true}
	pgUserID := pgtype.UUID{Bytes: uuid.MustParse(testNoteUserID), Valid: true}

	q := sqlcgen.New(pool)

	nodeID := "00000000-0000-0000-0000-000000000040"
	nodeUUID := pgtype.UUID{Bytes: uuid.MustParse(nodeID), Valid: true}
	q.UpsertNoteNode(ctx, sqlcgen.UpsertNoteNodeParams{
		ID:        nodeUUID,
		NoteID:    pgNoteID,
		Type:      "text",
		Data:      []byte(`{"text":"hello"}`),
		CreatedAt: pgtype.Timestamptz{Time: time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC), Valid: true},
		DeletedAt: pgtype.Timestamptz{Valid: false},
	})

	taskID := "00000000-0000-0000-0000-000000000050"
	taskUUID := pgtype.UUID{Bytes: uuid.MustParse(taskID), Valid: true}
	q.UpsertTask(ctx, sqlcgen.UpsertTaskParams{
		ID:        taskUUID,
		UserID:    pgUserID,
		NoteID:    pgNoteID,
		Title:     "Buy milk",
		Status:    "open",
		CreatedAt: pgtype.Timestamptz{Time: time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC), Valid: true},
		DeletedAt: pgtype.Timestamptz{Valid: false},
	})

	update, err := ReconstructYDocFromNodes(ctx, pool, testNoteID)
	require.NoError(t, err)
	require.NotEmpty(t, update)

	doc := crdt.New(crdt.WithGC(false))
	err = crdt.ApplyUpdateV1(doc, update, nil)
	require.NoError(t, err)

	nodesMap := doc.GetMap("nodes")
	assert.Greater(t, len(nodesMap.Keys()), 0)

	raw, ok := nodesMap.Get(nodeID)
	require.True(t, ok)
	var rehydrated noteNodeJSON
	err = json.Unmarshal([]byte(raw.(string)), &rehydrated)
	require.NoError(t, err)
	assert.Equal(t, "text", rehydrated.Type)
	assert.Contains(t, string(rehydrated.Data), "hello")

	tasksMap := doc.GetMap("tasks")
	assert.Greater(t, len(tasksMap.Keys()), 0)
	raw2, ok := tasksMap.Get(taskID)
	require.True(t, ok)
	var rehydratedTask taskJSON
	err = json.Unmarshal([]byte(raw2.(string)), &rehydratedTask)
	require.NoError(t, err)
	assert.Equal(t, "Buy milk", rehydratedTask.Title)
	assert.Equal(t, "open", rehydratedTask.Status)

	// Verify YText was created for the node's text content
	textType := doc.GetText("content/" + nodeID)
	require.NotNil(t, textType)
	assert.Equal(t, "hello", textType.ToString())
}

func TestProjectToDB_HandlesEmptyUpdate(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	doc := crdt.New(crdt.WithGC(false))
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	err := projectUpdateHelper(ctx, pool, testNoteID, update)
	require.NoError(t, err)
}

func TestReconstructYDocFromNodes_IncludesYText(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	pgNoteID := pgtype.UUID{Bytes: uuid.MustParse(testNoteID), Valid: true}
	q := sqlcgen.New(pool)

	nodeID := "00000000-0000-0000-0000-000000000060"
	nodeUUID := pgtype.UUID{Bytes: uuid.MustParse(nodeID), Valid: true}
	q.UpsertNoteNode(ctx, sqlcgen.UpsertNoteNodeParams{
		ID:        nodeUUID,
		NoteID:    pgNoteID,
		Type:      "text",
		Data:      []byte(`{"text":"hello world","level":2}`),
		CreatedAt: pgtype.Timestamptz{Time: time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC), Valid: true},
		DeletedAt: pgtype.Timestamptz{Valid: false},
	})

	update, err := ReconstructYDocFromNodes(ctx, pool, testNoteID)
	require.NoError(t, err)
	require.NotEmpty(t, update)

	doc := crdt.New(crdt.WithGC(false))
	err = crdt.ApplyUpdateV1(doc, update, nil)
	require.NoError(t, err)

	// Verify YText exists for this node
	textType := doc.GetText("content/" + nodeID)
	require.NotNil(t, textType)
	assert.Equal(t, "hello world", textType.ToString())

	// Verify YMap still has the full metadata
	nodesMap := doc.GetMap("nodes")
	raw, ok := nodesMap.Get(nodeID)
	require.True(t, ok)
	var rehydrated noteNodeJSON
	err = json.Unmarshal([]byte(raw.(string)), &rehydrated)
	require.NoError(t, err)
	assert.Equal(t, "text", rehydrated.Type)
}

func TestProjectToDBTx_RoundTripsFullDoc(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	nodeID := "00000000-0000-0000-0000-000000000070"
	nodeJSON := fmt.Sprintf(`{"id":"%s","parentId":"","position":0,"type":"text","data":{"text":"hello"}}`, nodeID)
	seed := makeNodeUpdate(t, map[string]string{nodeID: nodeJSON})
	require.NoError(t, projectUpdateHelper(ctx, pool, testNoteID, seed))

	docPartial := crdt.New(crdt.WithGC(false))
	docPartial.Transact(func(txn *crdt.Transaction) {
		docPartial.GetText("content/"+nodeID).Insert(txn, 0, " CHANGED", nil)
	})
	partial := crdt.EncodeStateAsUpdateV1(docPartial, nil)

	doc := crdt.New(crdt.WithGC(false))
	require.NoError(t, crdt.ApplyUpdateV1(doc, seed, nil))
	require.NoError(t, crdt.ApplyUpdateV1(doc, partial, nil))

	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	require.NoError(t, ProjectToDBTxFromDoc(ctx, tx, doc, testNoteID))
	require.NoError(t, tx.Commit(ctx))

	var dataJSON []byte
	require.NoError(t, pool.QueryRow(ctx, "SELECT data FROM note_nodes WHERE id = $1", nodeID).Scan(&dataJSON))
	assert.Contains(t, string(dataJSON), "hello CHANGED")
}

func TestLoadYDocState_RejectsMalformedUUID(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	_, err := LoadYDocState(ctx, pool, "not-a-uuid")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "parse note id")
}

func TestReconstructYDocFromNodes_EmptyNote(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	update, err := ReconstructYDocFromNodes(ctx, pool, testNoteID)
	require.NoError(t, err)

	doc := crdt.New(crdt.WithGC(false))
	err = crdt.ApplyUpdateV1(doc, update, nil)
	require.NoError(t, err)

	nodesMap := doc.GetMap("nodes")
	tasksMap := doc.GetMap("tasks")
	assert.Empty(t, nodesMap.Keys())
	assert.Empty(t, tasksMap.Keys())
}
