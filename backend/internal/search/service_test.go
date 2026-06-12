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
	searchHybrid func(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error)
}

func (m *mockQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	return m.searchHybrid(ctx, arg)
}

func makeUUID(b byte) pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte{b}, Valid: true}
}

func TestService_Search(t *testing.T) {
	userID := makeUUID(1)
	var called bool
	svc := NewService(&mockQuerier{
		searchHybrid: func(_ context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
			called = true
			if arg.UserID != userID {
				t.Errorf("expected userID %v, got %v", userID, arg.UserID)
			}
			if arg.Query != "test:*" {
				t.Errorf("expected query 'test:*', got %q", arg.Query)
			}
			if arg.Limit != 10 {
				t.Errorf("expected limit 10, got %d", arg.Limit)
			}
			return []sqlcgen.SearchNotesHybridRow{
				{ID: makeUUID(30), Title: pgtype.Text{String: "Hybrid Note", Valid: true}, Content: "hybrid", Score: 0.9},
			}, nil
		},
	}, llm.NewEmbeddingClient("", "", ""))

	results, err := svc.Search(context.Background(), userID, "test", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("SearchNotesHybrid was not called")
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Title != "Hybrid Note" {
		t.Errorf("expected title 'Hybrid Note', got %q", results[0].Title)
	}
}
