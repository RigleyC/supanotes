package tools

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
)

type WorkingMemoryStore interface {
	Get(ctx context.Context, userID, sessionID pgtype.UUID, key string) (string, error)
	Set(ctx context.Context, userID, sessionID pgtype.UUID, key, value string) error
}

type GetWorkingMemoryTool struct {
	wm WorkingMemoryStore
}

func (t *GetWorkingMemoryTool) Name() string { return "get_working_memory" }
func (t *GetWorkingMemoryTool) Description() string {
	return "Retrieve a value from the working session memory"
}
func (t *GetWorkingMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}`
}
func (t *GetWorkingMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Key string `json:"key"`
	}](argsJSON)
	if err != nil {
		return "", fmt.Errorf("get_working_memory: %w", err)
	}
	val, err := t.wm.Get(ctx, userID, parseSessionID(sessionID), args.Key)
	if err != nil {
		return "", fmt.Errorf("get_working_memory: %w", err)
	}
	return fmt.Sprintf("Working memory [%s]: %s", args.Key, val), nil
}

type SetWorkingMemoryTool struct {
	wm WorkingMemoryStore
}

func (t *SetWorkingMemoryTool) Name() string { return "set_working_memory" }
func (t *SetWorkingMemoryTool) Description() string {
	return "Store a value in the working session memory. Use this to remember information relevant to the current conversation (e.g., the user's current goal, a decision made mid-conversation, or context that should persist across turns)."
}
func (t *SetWorkingMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"key":{"type":"string"},"value":{"type":"string"}},"required":["key","value"]}`
}
func (t *SetWorkingMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Key   string `json:"key"`
		Value string `json:"value"`
	}](argsJSON)
	if err != nil {
		return "", fmt.Errorf("set_working_memory: %w", err)
	}
	if err := t.wm.Set(ctx, userID, parseSessionID(sessionID), args.Key, args.Value); err != nil {
		return "", fmt.Errorf("set_working_memory: %w", err)
	}
	return fmt.Sprintf("Working memory [%s] set", args.Key), nil
}
