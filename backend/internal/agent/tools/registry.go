package tools

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/routines"
	"github.com/RigleyC/supanotes/internal/soul"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type ToolExecutor interface {
	Name() string
	Description() string
	SchemaJSON() string
	Label() string
	Summary(rawOutput string) string
	Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error)
}

type defaultToolExecutor struct{}

func (defaultToolExecutor) Name() string                                          { return "" }
func (defaultToolExecutor) Description() string                                   { return "" }
func (defaultToolExecutor) SchemaJSON() string                                    { return "{}" }
func (defaultToolExecutor) Label() string                                         { return "Executando..." }
func (defaultToolExecutor) Summary(string) string                                 { return "[Tool executed]" }
func (defaultToolExecutor) Execute(context.Context, pgtype.UUID, string, string) (string, error) {
	return "", fmt.Errorf("unknown tool")
}

type ToolRegistry struct {
	tools map[string]ToolExecutor
}

func NewToolRegistry(
	q sqlcgen.Querier,
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
	memoriesSvc *memories.Service,
	routinesSvc *routines.Service,
	soulSvc *soul.Service,
	embedCL *llm.EmbeddingClient,
	llmFact llm.Factory,
	wm WorkingMemoryStore,
) *ToolRegistry {
	registry := &ToolRegistry{
		tools: make(map[string]ToolExecutor),
	}

	executors := []ToolExecutor{
		&AddNoteTool{notesSvc: notesSvc},
		&AddTaskTool{tasksSvc: tasksSvc},
		&SaveMemoryTool{memoriesSvc: memoriesSvc},
		&CompleteTaskTool{tasksSvc: tasksSvc},
		&QueryTasksTool{tasksSvc: tasksSvc, q: q},
		&ListMemoriesTool{memoriesSvc: memoriesSvc},
		&SearchNotesTool{q: q, embedCL: embedCL},
		&GetSoulTool{q: q},
		&ListRoutinesTool{routinesSvc: routinesSvc},
		&TestDailyBriefTool{routinesSvc: routinesSvc},
		&TestWeeklyBriefTool{routinesSvc: routinesSvc},
		&SetDailyBriefScheduleTool{routinesSvc: routinesSvc},
		&SetWeeklyBriefScheduleTool{routinesSvc: routinesSvc},
		&GetNotesTool{notesSvc: notesSvc},
		&GetNoteTool{notesSvc: notesSvc},
		&AppendToNoteTool{notesSvc: notesSvc},
		&LinkNotesTool{q: q, notesSvc: notesSvc},
		&DeleteMemoryTool{memoriesSvc: memoriesSvc},
		&UpdateSoulTool{soulSvc: soulSvc},
		&UpdateTaskTool{tasksSvc: tasksSvc},
		&GetVaultContextTool{q: q},
		&GetWorkingMemoryTool{wm: wm},
		&SetWorkingMemoryTool{wm: wm},
		&UpdateUserProfileTool{q: q},
	}

	for _, e := range executors {
		registry.tools[e.Name()] = e
	}

	return registry
}

type ToolRisk string

const (
	ToolRiskRead           ToolRisk = "read"
	ToolRiskLowWrite       ToolRisk = "low_write"
	ToolRiskSensitiveWrite ToolRisk = "sensitive_write"
)

func (tr *ToolRegistry) Risk(toolName string) ToolRisk {
	switch toolName {
	case "search_notes", "get_note", "get_notes", "query_tasks", "list_memories", "get_soul", "list_routines", "get_vault_context", "test_daily_brief", "test_weekly_brief", "get_working_memory":
		return ToolRiskRead
	case "add_note", "add_task", "save_memory", "update_soul", "update_user_profile", "link_notes", "set_working_memory", "append_to_note":
		return ToolRiskLowWrite
	case "delete_memory", "set_daily_brief_schedule", "set_weekly_brief_schedule", "update_task", "complete_task":
		return ToolRiskSensitiveWrite
	default:
		return ToolRiskSensitiveWrite
	}
}

func (tr *ToolRegistry) Get(name string) ToolExecutor {
	exec, ok := tr.tools[name]
	if !ok {
		return defaultToolExecutor{}
	}
	return exec
}

func (tr *ToolRegistry) GetTools() []llm.Tool {
	var result []llm.Tool
	for _, e := range tr.tools {
		result = append(result, llm.Tool{
			Name:        e.Name(),
			Description: e.Description(),
			SchemaJSON:  e.SchemaJSON(),
		})
	}
	return result
}

func (tr *ToolRegistry) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, toolName string, argsJSON string) (string, error) {
	executor, ok := tr.tools[toolName]
	if !ok {
		return "", fmt.Errorf("unknown tool: %s", toolName)
	}
	return executor.Execute(ctx, userID, sessionID, argsJSON)
}
