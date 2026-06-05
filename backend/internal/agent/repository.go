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
