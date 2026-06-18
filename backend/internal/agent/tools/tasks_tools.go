package tools

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AddTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *AddTaskTool) Name() string        { return "add_task" }
func (t *AddTaskTool) Description() string { return "Create a new task. Optionally link to a note via note_id. Set recurrence for repeating tasks (daily/weekdays/weekly/monthly). Set due_date (YYYY-MM-DD) for deadline tracking." }
func (t *AddTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"title":{"type":"string"},"note_id":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date"},"recurrence":{"type":"string","enum":["none","daily","weekdays","weekly","monthly"]}},"required":["title"]}`
}
func (t *AddTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
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
	task, err := t.tasksSvc.CreateTask(ctx, userID, noteID, args.Title, dueDateTime, args.Recurrence, 0)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Task created with ID: %s", formatID(task.ID)), nil
}

type CompleteTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *CompleteTaskTool) Name() string        { return "complete_task" }
func (t *CompleteTaskTool) Description() string { return "Mark a task as done. Use this when the user says they completed something (e.g., 'comprei o arroz', 'fiz o treino', 'terminei o relatório'). Pass the task_id from get_open_tasks or get_today_tasks." }
func (t *CompleteTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"}},"required":["task_id"]}`
}
func (t *CompleteTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
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

type GetOpenTasksTool struct {
	tasksSvc *tasks.Service
}

func (t *GetOpenTasksTool) Name() string        { return "get_open_tasks" }
func (t *GetOpenTasksTool) Description() string { return "List all open (pending) tasks across all notes. Returns task ID, title, and note title. Use this when the user asks what they have pending or need to do." }
func (t *GetOpenTasksTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetOpenTasksTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	openStatus := "open"
	tasksList, err := t.tasksSvc.GetTasks(ctx, userID, nil, &openStatus, nil, nil, 100, 0)
	if err != nil {
		return "", err
	}
	result := "Open Tasks:\n"
	for _, task := range tasksList {
		result += fmt.Sprintf("- [%s] %s\n", formatID(task.ID), task.Title)
	}
	return result, nil
}

type GetTodayTasksTool struct {
	tasksSvc *tasks.Service
}

func (t *GetTodayTasksTool) Name() string        { return "get_today_tasks" }
func (t *GetTodayTasksTool) Description() string { return "List tasks due today or overdue. Returns task ID, title, status, due date, and recurrence. Use this when the user asks what they have for today." }
func (t *GetTodayTasksTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetTodayTasksTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	ts, err := t.tasksSvc.GetTodayTasks(ctx, userID)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for _, task := range ts {
		b.WriteString(fmt.Sprintf("- [%s] %s (Due: %v, Recurrence: %s)\n", task.Status, task.Title, task.DueDate.Time, task.Recurrence.String))
	}
	if b.Len() == 0 {
		return "No tasks for today or overdue", nil
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
func (t *UpdateTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"},"title":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date, omit to leave unchanged"},"clear_due_date":{"type":"boolean","description":"Set to true to remove the due date"},"recurrence":{"type":"string","enum":["daily","weekdays","weekly","monthly"]},"clear_recurrence":{"type":"boolean","description":"Set to true to remove the recurrence"}},"required":["task_id"]}`
}
func (t *UpdateTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
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
