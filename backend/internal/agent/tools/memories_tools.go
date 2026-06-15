package tools

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type SaveMemoryTool struct {
	memoriesSvc *memories.Service
}

func (t *SaveMemoryTool) Name() string { return "save_memory" }
func (t *SaveMemoryTool) Description() string {
	return "Save an important fact or preference about the user"
}
func (t *SaveMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *SaveMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	mem, err := t.memoriesSvc.CreateMemory(ctx, userID, args.Content)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Memory saved with ID: %s", formatID(mem.ID)), nil
}

type ListMemoriesTool struct {
	memoriesSvc *memories.Service
}

func (t *ListMemoriesTool) Name() string        { return "list_memories" }
func (t *ListMemoriesTool) Description() string { return "List all saved memories for the user" }
func (t *ListMemoriesTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *ListMemoriesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	mems, err := t.memoriesSvc.GetMemories(ctx, userID, 100, 0)
	if err != nil {
		return "", err
	}
	result := "Memories:\n"
	for _, m := range mems {
		result += fmt.Sprintf("- [%s] %s\n", formatID(m.ID), m.Content)
	}
	return result, nil
}

type DeleteMemoryTool struct {
	memoriesSvc *memories.Service
}

func (t *DeleteMemoryTool) Name() string        { return "delete_memory" }
func (t *DeleteMemoryTool) Description() string { return "Delete a specific memory by ID" }
func (t *DeleteMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"memory_id":{"type":"string"}},"required":["memory_id"]}`
}
func (t *DeleteMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		MemoryID string `json:"memory_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	mid, err := uid.UUIDFromString(args.MemoryID)
	if err != nil {
		return "", err
	}
	if err := t.memoriesSvc.DeleteMemory(ctx, mid, userID); err != nil {
		return "", err
	}
	return "Memory deleted", nil
}
