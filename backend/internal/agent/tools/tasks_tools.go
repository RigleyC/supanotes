package tools

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AddTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *AddTaskTool) Name() string { return "add_task" }
func (t *AddTaskTool) Description() string {
	return "Create a new task. Optionally link to a note via note_id. Set recurrence for repeating tasks (daily/weekdays/weekly/monthly). Set due_date (YYYY-MM-DD) for deadline tracking."
}
func (t *AddTaskTool) Label() string { return "Atualizando tarefas" }
func (t *AddTaskTool) Summary(string) string { return "[AddTaskTool executed successfully]" }

func (t *AddTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"title":{"type":"string"},"note_id":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date"},"recurrence":{"type":"string","enum":["none","daily","weekdays","weekly","monthly"]}},"required":["title"]}`
}
func (t *AddTaskTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Title      string  `json:"title"`
		NoteID     *string `json:"note_id"`
		DueDate    *string `json:"due_date"`
		Recurrence *string `json:"recurrence"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	var noteID pgtype.UUID
	if args.NoteID != nil {
		nid, err := uid.UUIDFromString(*args.NoteID)
		if err != nil {
			return "", fmt.Errorf("invalid note_id: %w", err)
		}
		noteID = nid
	}
	var dueDateTime *time.Time
	if args.DueDate != nil {
		t, err := time.Parse("2006-01-02", *args.DueDate)
		if err != nil {
			return "", fmt.Errorf("invalid due_date format, use YYYY-MM-DD: %w", err)
		}
		dueDateTime = &t
	}
	task, err := t.tasksSvc.CreateTask(ctx, userID, noteID, args.Title, dueDateTime, args.Recurrence, "0")
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Task created with ID: %s", formatID(task.ID)), nil
}

type CompleteTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *CompleteTaskTool) Name() string { return "complete_task" }
func (t *CompleteTaskTool) Description() string {
	return "Mark a task as done. Use this when the user says they completed something (e.g., 'comprei o arroz', 'fiz o treino', 'terminei o relatório'). Pass the task_id from get_open_tasks or get_today_tasks."
}
func (t *CompleteTaskTool) Label() string { return "Atualizando tarefas" }
func (t *CompleteTaskTool) Summary(string) string { return "[CompleteTaskTool executed successfully]" }

func (t *CompleteTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"}},"required":["task_id"]}`
}
func (t *CompleteTaskTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		TaskID string `json:"task_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	tid, err := uid.UUIDFromString(args.TaskID)
	if err != nil {
		return "", err
	}
	_, err = t.tasksSvc.CompleteTask(ctx, userID, tid)
	if err != nil {
		return "", err
	}
	return "Task marked as completed", nil
}

type QueryTasksTool struct {
	tasksSvc *tasks.Service
	q        sqlcgen.Querier
}

func (t *QueryTasksTool) Name() string { return "query_tasks" }
func (t *QueryTasksTool) Description() string {
	return "Search and filter tasks. Use this when the user asks for their open tasks, today's tasks, or searches for a specific task. You can filter by status (open/done/all), timeframe (today/overdue/all), and keyword query."
}
func (t *QueryTasksTool) Label() string { return "Consultando tarefas" }
func (t *QueryTasksTool) Summary(string) string { return "[Task query completed]" }

func (t *QueryTasksTool) SchemaJSON() string {
	return `{"type":"object","properties":{"status":{"type":"string","enum":["open","done","all"],"description":"Filter by status. Default: open"},"timeframe":{"type":"string","enum":["today","overdue","all"],"description":"Filter by timeframe. 'today' means due today or earlier. 'overdue' means due before today. Default: all"},"query":{"type":"string","description":"Optional keyword to search in task titles"}},"required":[]}`
}
func (t *QueryTasksTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Status    *string `json:"status"`
		Timeframe *string `json:"timeframe"`
		Query     *string `json:"query"`
	}](argsJSON)
	if err != nil {
		return "", err
	}

	var statusFilter *string
	if args.Status == nil {
		open := "open"
		statusFilter = &open
	} else if *args.Status != "all" {
		statusFilter = args.Status
	}

	var tzLoc *time.Location = time.UTC
	userSettings, err := t.q.GetUserSettings(ctx, userID)
	if err == nil && userSettings.Timezone != "" {
		if loc, locErr := time.LoadLocation(userSettings.Timezone); locErr == nil {
			tzLoc = loc
		}
	}

	limit := int32(50)
	var tasksList []sqlcgen.Task

	if args.Query != nil && *args.Query != "" {
		tasksList, err = t.tasksSvc.SearchTasks(ctx, userID, *args.Query, statusFilter, limit, 0)
		if err != nil {
			return "", err
		}
	} else if args.Timeframe != nil && (*args.Timeframe == "today" || *args.Timeframe == "overdue") {
		tasksList, err = t.tasksSvc.GetTodayTasksInTimezone(ctx, userID, tzLoc)
		if err != nil {
			return "", err
		}
		if *args.Timeframe == "overdue" {
			now := time.Now().In(tzLoc)
			// Today date boundary
			today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
			var overdue []sqlcgen.Task
			for _, task := range tasksList {
				if task.DueDate.Valid && task.DueDate.Time.Before(today) {
					overdue = append(overdue, task)
				}
			}
			tasksList = overdue
		}
	} else {
		tasksList, err = t.tasksSvc.GetTasks(ctx, userID, nil, statusFilter, nil, nil, limit, 0)
		if err != nil {
			return "", err
		}
	}

	var b strings.Builder
	for _, task := range tasksList {
		due := ""
		if task.DueDate.Valid {
			due = fmt.Sprintf(" (Due: %s)", task.DueDate.Time.Format("2006-01-02"))
		}
		b.WriteString(fmt.Sprintf("- [%s] [%s] %s%s\n", task.Status, formatID(task.ID), task.Title, due))
	}
	if b.Len() == 0 {
		return "No matching tasks found", nil
	}
	return b.String(), nil
}

type UpdateTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *UpdateTaskTool) Name() string { return "update_task" }
func (t *UpdateTaskTool) Description() string {
	return "Update a task's title, due_date, or recurrence"
}
func (t *UpdateTaskTool) Label() string { return "Atualizando tarefas" }
func (t *UpdateTaskTool) Summary(string) string { return "[UpdateTaskTool executed successfully]" }

func (t *UpdateTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"},"title":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date, omit to leave unchanged"},"clear_due_date":{"type":"boolean","description":"Set to true to remove the due date"},"recurrence":{"type":"string","enum":["daily","weekdays","weekly","monthly"]},"clear_recurrence":{"type":"boolean","description":"Set to true to remove the recurrence"}},"required":["task_id"]}`
}
func (t *UpdateTaskTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		TaskID          string  `json:"task_id"`
		Title           *string `json:"title"`
		DueDate         *string `json:"due_date"`
		ClearDueDate    bool    `json:"clear_due_date"`
		Recurrence      *string `json:"recurrence"`
		ClearRecurrence bool    `json:"clear_recurrence"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	tid, err := uid.UUIDFromString(args.TaskID)
	if err != nil {
		return "", err
	}
	var dueDateTime *time.Time
	if args.DueDate != nil {
		t, err := time.Parse("2006-01-02", *args.DueDate)
		if err != nil {
			return "", fmt.Errorf("invalid due_date format, use YYYY-MM-DD: %w", err)
		}
		dueDateTime = &t
	}
	updated, err := t.tasksSvc.UpdateTask(ctx, userID, tid, tasks.UpdateTaskOpts{
		Title:           args.Title,
		DueDate:         dueDateTime,
		ClearDueDate:    args.ClearDueDate,
		Recurrence:      args.Recurrence,
		ClearRecurrence: args.ClearRecurrence,
	})
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Task updated: [%s] %s", formatID(updated.ID), updated.Title), nil
}
