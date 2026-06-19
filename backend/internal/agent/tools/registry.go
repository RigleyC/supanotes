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
	Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error)
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
) *ToolRegistry {
	registry := &ToolRegistry{
		tools: make(map[string]ToolExecutor),
	}

	executors := []ToolExecutor{
		&AddNoteTool{notesSvc: notesSvc},
		&AddTaskTool{tasksSvc: tasksSvc},
		&SaveMemoryTool{memoriesSvc: memoriesSvc},
		&CompleteTaskTool{tasksSvc: tasksSvc},
		&QueryTasksTool{tasksSvc: tasksSvc},
		&ListMemoriesTool{memoriesSvc: memoriesSvc},
		&GetInboxNoteTool{notesSvc: notesSvc},
		&AppendToInboxTool{notesSvc: notesSvc},
		&SearchNotesTool{q: q, embedCL: embedCL},
		&GetSoulTool{q: q},
		&ListRoutinesTool{routinesSvc: routinesSvc},
		&TestDailyBriefTool{routinesSvc: routinesSvc},
		&TestWeeklyBriefTool{routinesSvc: routinesSvc},
		&SetDailyBriefScheduleTool{routinesSvc: routinesSvc},
		&SetWeeklyBriefScheduleTool{routinesSvc: routinesSvc},
		&GetNotesTool{notesSvc: notesSvc},
		&GetNoteTool{notesSvc: notesSvc},
		&UpdateNoteTool{notesSvc: notesSvc},
		&AppendToNoteTool{notesSvc: notesSvc},
		&LinkNotesTool{q: q, notesSvc: notesSvc},
		&DeleteMemoryTool{memoriesSvc: memoriesSvc},
		&UpdateSoulTool{soulSvc: soulSvc},
		&UpdateTaskTool{tasksSvc: tasksSvc},
		&GetVaultContextTool{q: q},
		&PlanInboxOrganizationTool{notesSvc: notesSvc, llmClient: llmFact.For(llm.TaskTypeInboxOrganize)},
		&ApplyInboxOrganizationTool{notesSvc: notesSvc},
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
	case "search_notes", "get_note", "get_notes", "query_tasks", "list_memories", "get_soul", "list_routines", "get_vault_context", "get_inbox_note", "plan_inbox_organization", "test_daily_brief", "test_weekly_brief":
		return ToolRiskRead
	case "add_note", "add_task", "save_memory", "append_to_inbox", "update_soul", "link_notes":
		return ToolRiskLowWrite
	case "update_note", "append_to_note", "delete_memory", "apply_inbox_organization", "set_daily_brief_schedule", "set_weekly_brief_schedule", "update_task", "complete_task":
		return ToolRiskSensitiveWrite
	default:
		return ToolRiskSensitiveWrite
	}
}

func (tr *ToolRegistry) Label(toolName string) string {
	switch toolName {
	case "search_notes":
		return "Buscando notas"
	case "get_note", "get_notes":
		return "Lendo notas"
	case "query_tasks":
		return "Consultando tarefas"
	case "add_note", "append_to_note", "append_to_inbox":
		return "Atualizando notas"
	case "add_task", "update_task", "complete_task":
		return "Atualizando tarefas"
	default:
		return "Executando acao"
	}
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

func (tr *ToolRegistry) Execute(ctx context.Context, userID pgtype.UUID, toolName string, argsJSON string) (string, error) {
	executor, ok := tr.tools[toolName]
	if !ok {
		return "", fmt.Errorf("unknown tool: %s", toolName)
	}
	return executor.Execute(ctx, userID, argsJSON)
}
