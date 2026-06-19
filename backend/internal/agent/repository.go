package agent

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetMessages(ctx context.Context, userID, sessionID pgtype.UUID, limit, offset int32) ([]sqlcgen.Message, error)
	CreateMessage(ctx context.Context, userID, sessionID pgtype.UUID, role, content string, toolCalls []byte, toolCallID *string) (sqlcgen.Message, error)
	DeleteSessionMessages(ctx context.Context, userID, sessionID pgtype.UUID) error
	CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error)
	CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error)
	CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error)
	CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error)
	CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error)
	GetPendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID) (sqlcgen.PendingToolConfirmation, error)
	ResolvePendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID, status string) (sqlcgen.PendingToolConfirmation, error)
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) GetMessages(ctx context.Context, userID, sessionID pgtype.UUID, limit, offset int32) ([]sqlcgen.Message, error) {
	return r.q.GetMessages(ctx, sqlcgen.GetMessagesParams{
		UserID:    userID,
		SessionID: sessionID,
		Limit:     limit,
		Offset:    offset,
	})
}

func (r *repository) CreateMessage(ctx context.Context, userID, sessionID pgtype.UUID, role, content string, toolCalls []byte, toolCallID *string) (sqlcgen.Message, error) {
	var tcID pgtype.Text
	if toolCallID != nil {
		tcID = pgtype.Text{String: *toolCallID, Valid: true}
	}

	return r.q.CreateMessage(ctx, sqlcgen.CreateMessageParams{
		UserID:     userID,
		SessionID:  sessionID,
		Role:       role,
		Content:    content,
		ToolCalls:  toolCalls,
		ToolCallID: tcID,
	})
}

func (r *repository) DeleteSessionMessages(ctx context.Context, userID, sessionID pgtype.UUID) error {
	return r.q.DeleteSessionMessages(ctx, sqlcgen.DeleteSessionMessagesParams{
		UserID:    userID,
		SessionID: sessionID,
	})
}

func (r *repository) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountNotes(ctx, userID)
}

func (r *repository) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountTasks(ctx, userID)
}

func (r *repository) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountOpenTasks(ctx, userID)
}

func (r *repository) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountCompletedTasks(ctx, userID)
}

func (r *repository) CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error) {
	return r.q.CreatePendingToolConfirmation(ctx, sqlcgen.CreatePendingToolConfirmationParams{
		UserID:    userID,
		SessionID: sessionID,
		ToolName:  toolName,
		ArgsJson:  []byte(argsJSON),
	})
}

func (r *repository) GetPendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID) (sqlcgen.PendingToolConfirmation, error) {
	return r.q.GetPendingToolConfirmation(ctx, sqlcgen.GetPendingToolConfirmationParams{
		ID:     id,
		UserID: userID,
	})
}

func (r *repository) ResolvePendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID, status string) (sqlcgen.PendingToolConfirmation, error) {
	return r.q.ResolvePendingToolConfirmation(ctx, sqlcgen.ResolvePendingToolConfirmationParams{
		ID:     id,
		UserID: userID,
		Status: status,
	})
}
