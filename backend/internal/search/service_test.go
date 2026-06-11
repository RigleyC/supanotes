package search

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type mockQuerier struct {
	sqlcgen.Querier
	searchFTS      func(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error)
	searchSemantic func(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error)
	searchHybrid   func(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error)
}

func (m *mockQuerier) SearchNotesFTS(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	return m.searchFTS(ctx, arg)
}

func (m *mockQuerier) SearchNotesSemantic(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	return m.searchSemantic(ctx, arg)
}

func (m *mockQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	return m.searchHybrid(ctx, arg)
}

func makeUUID(b byte) pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte{b}, Valid: true}
}

func TestService_SearchFTS(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchFTS: func(_ context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
			called = true
			if arg.UserID != userID {
				t.Errorf("expected userID %v, got %v", userID, arg.UserID)
			}
			if arg.Query != "hello" {
				t.Errorf("expected query 'hello', got %q", arg.Query)
			}
			if arg.Limit != 5 {
				t.Errorf("expected limit 5, got %d", arg.Limit)
			}
			return []sqlcgen.SearchNotesFTSRow{
				{ID: makeUUID(10), Title: pgtype.Text{String: "Note 1", Valid: true}, Content: "content 1", Score: 0.5},
			}, nil
		},
	}, nil)

	results, err := svc.Search(context.Background(), userID, "hello", "fts", 5)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("SearchNotesFTS was not called")
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Title != "Note 1" {
		t.Errorf("expected title 'Note 1', got %q", results[0].Title)
	}
}

func TestService_SearchSemantic(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchSemantic: func(_ context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
			called = true
			if arg.UserID != userID {
				t.Errorf("expected userID %v, got %v", userID, arg.UserID)
			}
			if arg.Limit != 10 {
				t.Errorf("expected limit 10, got %d", arg.Limit)
			}
			return []sqlcgen.SearchNotesSemanticRow{
				{ID: makeUUID(20), Title: pgtype.Text{String: "Sem Note", Valid: true}, Content: "sem content", Score: 0.8},
			}, nil
		},
	}, llm.NewEmbeddingClient("", "", ""))

	results, err := svc.Search(context.Background(), userID, "test", "semantic", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("SearchNotesSemantic was not called")
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
}

func TestService_SearchHybrid(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchHybrid: func(_ context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
			called = true
			if arg.UserID != userID {
				t.Errorf("expected userID %v, got %v", userID, arg.UserID)
			}
			return []sqlcgen.SearchNotesHybridRow{
				{ID: makeUUID(30), Title: pgtype.Text{String: "Hybrid Note", Valid: true}, Content: "hybrid", Score: 0.9},
			}, nil
		},
	}, llm.NewEmbeddingClient("", "", ""))

	results, err := svc.Search(context.Background(), userID, "test", "hybrid", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("SearchNotesHybrid was not called")
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
}

func TestService_SearchDefaultMode(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchFTS: func(_ context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
			called = true
			return nil, nil
		},
	}, nil)

	_, err := svc.Search(context.Background(), userID, "test", "unknown", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("expected FTS as default mode")
	}
}
