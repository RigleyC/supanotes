package notes

import (
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestRenderNoteToMarkdown(t *testing.T) {
	id1 := pgtype.UUID{Bytes: uuid.New(), Valid: true}
	id2 := pgtype.UUID{Bytes: uuid.New(), Valid: true}

	nodes := []sqlcgen.NoteNode{
		{ID: id1, Type: "paragraph", Data: []byte(`{"text": "Hello world"}`)},
		{ID: id2, Type: "task", Data: []byte(`{"text": "Buy milk"}`)},
	}
	tasks := map[pgtype.UUID]sqlcgen.Task{
		id2: {Status: "open"},
	}

	markdown := RenderNoteToMarkdown(nodes, tasks)
	expected := "Hello world\n- [ ] Buy milk\n"

	if markdown != expected {
		t.Errorf("Expected %q, got %q", expected, markdown)
	}
}

func TestRenderNoteToMarkdown_DoneTask(t *testing.T) {
	id := pgtype.UUID{Bytes: uuid.New(), Valid: true}

	nodes := []sqlcgen.NoteNode{
		{ID: id, Type: "task", Data: []byte(`{"text": "Buy milk"}`)},
	}
	tasks := map[pgtype.UUID]sqlcgen.Task{
		id: {Status: "done"},
	}

	markdown := RenderNoteToMarkdown(nodes, tasks)
	expected := "- [x] Buy milk\n"

	if markdown != expected {
		t.Errorf("Expected %q, got %q", expected, markdown)
	}
}
