package tools

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/soul"
)

type GetSoulTool struct {
	q sqlcgen.Querier
}

func (t *GetSoulTool) Name() string { return "get_soul" }
func (t *GetSoulTool) Description() string {
	return "Get the agent's Soul (personality and core directives)"
}
func (t *GetSoulTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetSoulTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	soul, err := t.q.GetSoul(ctx, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Soul:\n%s", soul.Personality), nil
}

type UpdateSoulTool struct {
	soulSvc *soul.Service
}

func (t *UpdateSoulTool) Name() string        { return "update_soul" }
func (t *UpdateSoulTool) Description() string { return "Update the agent's personality (Soul)" }
func (t *UpdateSoulTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *UpdateSoulTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	if _, err := t.soulSvc.Update(ctx, userID, args.Content); err != nil {
		return "", err
	}
	return "Soul updated", nil
}
