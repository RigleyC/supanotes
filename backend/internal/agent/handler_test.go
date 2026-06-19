package agent

import (
	"context"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type handlerTestRepo struct {
	pendingConfirmation sqlcgen.PendingToolConfirmation
}

func (r *handlerTestRepo) GetMessages(ctx context.Context, userID, sessionID pgtype.UUID, limit, offset int32) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (r *handlerTestRepo) CreateMessage(ctx context.Context, userID, sessionID pgtype.UUID, role, content string, toolCalls []byte, toolCallID *string) (sqlcgen.Message, error) {
	return sqlcgen.Message{}, nil
}
func (r *handlerTestRepo) DeleteSessionMessages(ctx context.Context, userID, sessionID pgtype.UUID) error {
	return nil
}
func (r *handlerTestRepo) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *handlerTestRepo) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *handlerTestRepo) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *handlerTestRepo) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *handlerTestRepo) CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error) {
	return sqlcgen.PendingToolConfirmation{}, nil
}
func (r *handlerTestRepo) GetPendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID) (sqlcgen.PendingToolConfirmation, error) {
	if r.pendingConfirmation.Status == "" {
		return sqlcgen.PendingToolConfirmation{}, fmt.Errorf("not found")
	}
	return r.pendingConfirmation, nil
}
func (r *handlerTestRepo) ResolvePendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID, status string) (sqlcgen.PendingToolConfirmation, error) {
	if r.pendingConfirmation.Status != "pending" {
		return sqlcgen.PendingToolConfirmation{}, fmt.Errorf("already resolved")
	}
	r.pendingConfirmation.Status = status
	return r.pendingConfirmation, nil
}

func TestResolveToolConfirmationHelperCancel(t *testing.T) {
	repo := &handlerTestRepo{
		pendingConfirmation: sqlcgen.PendingToolConfirmation{
			ID:        pgtype.UUID{Bytes: uuid.New(), Valid: true},
			UserID:    pgtype.UUID{Bytes: uuid.New(), Valid: true},
			SessionID: pgtype.UUID{Bytes: uuid.New(), Valid: true},
			ToolName:  "update_note",
			ArgsJson:  []byte(`{}`),
			Status:    "pending",
		},
	}
	h := NewHandler(NewLoop(&stubLoopRepo{}, nil, nil, nil), repo)

	resp, status, err := h.resolveToolConfirmation(
		context.Background(),
		repo.pendingConfirmation.UserID,
		uid.UUIDToString(repo.pendingConfirmation.ID),
		false,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != 200 {
		t.Fatalf("status: want 200, got %d", status)
	}
	if resp.Status != "cancelled" {
		t.Fatalf("status field: want cancelled, got %s", resp.Status)
	}
}

func TestResolveToolConfirmationHelperNotFound(t *testing.T) {
	repo := &handlerTestRepo{}
	h := NewHandler(NewLoop(&stubLoopRepo{}, nil, nil, nil), repo)

	_, status, err := h.resolveToolConfirmation(
		context.Background(),
		pgtype.UUID{},
		uuid.New().String(),
		true,
	)
	if err == nil {
		t.Fatal("expected error for not found")
	}
	if status != 404 {
		t.Fatalf("status: want 404, got %d", status)
	}
}
