package tools

import (
	"context"
	"encoding/json"
	"log/slog"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/routines"
)

type ListRoutinesTool struct {
	routinesSvc *routines.Service
}

func (t *ListRoutinesTool) Name() string { return "list_routines" }
func (t *ListRoutinesTool) Description() string {
	return "List all active routines (daily/weekly briefs)"
}
func (t *ListRoutinesTool) Label() string { return "Gerenciando rotinas" }
func (t *ListRoutinesTool) Summary(string) string { return "[ListRoutinesTool executed successfully]" }

func (t *ListRoutinesTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *ListRoutinesTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	b, err := json.Marshal(rs)
	if err != nil {
		slog.Error("marshal routines response", "error", err)
		return "", err
	}
	return string(b), nil
}

type TestDailyBriefTool struct {
	routinesSvc *routines.Service
}

func (t *TestDailyBriefTool) Name() string { return "test_daily_brief" }
func (t *TestDailyBriefTool) Description() string {
	return "Run a dry-run test of the daily brief routine"
}
func (t *TestDailyBriefTool) Label() string { return "Gerenciando rotinas" }
func (t *TestDailyBriefTool) Summary(string) string { return "[TestDailyBriefTool executed successfully]" }

func (t *TestDailyBriefTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *TestDailyBriefTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	resp, err := t.routinesSvc.TestRoutine(ctx, userID, "daily")
	if err != nil {
		return "", err
	}
	return resp, nil
}

type TestWeeklyBriefTool struct {
	routinesSvc *routines.Service
}

func (t *TestWeeklyBriefTool) Name() string { return "test_weekly_brief" }
func (t *TestWeeklyBriefTool) Description() string {
	return "Run a dry-run test of the weekly brief routine"
}
func (t *TestWeeklyBriefTool) Label() string { return "Gerenciando rotinas" }
func (t *TestWeeklyBriefTool) Summary(string) string { return "[TestWeeklyBriefTool executed successfully]" }

func (t *TestWeeklyBriefTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *TestWeeklyBriefTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	resp, err := t.routinesSvc.TestRoutine(ctx, userID, "weekly")
	if err != nil {
		return "", err
	}
	return resp, nil
}

type SetDailyBriefScheduleTool struct {
	routinesSvc *routines.Service
}

func (t *SetDailyBriefScheduleTool) Name() string { return "set_daily_brief_schedule" }
func (t *SetDailyBriefScheduleTool) Description() string {
	return "Update the cron schedule or status for the daily brief"
}
func (t *SetDailyBriefScheduleTool) Label() string { return "Gerenciando rotinas" }
func (t *SetDailyBriefScheduleTool) Summary(string) string { return "[SetDailyBriefScheduleTool executed successfully]" }

func (t *SetDailyBriefScheduleTool) SchemaJSON() string {
	return `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`
}
func (t *SetDailyBriefScheduleTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		CronExpr *string `json:"cron_expr"`
		Enabled  *bool   `json:"enabled"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	for _, r := range rs {
		if r.Type == "daily" {
			updated, err := t.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
			if err != nil {
				return "", err
			}
			b, err := json.Marshal(updated)
			if err != nil {
				slog.Error("marshal updated daily routine", "error", err)
				return "", err
			}
			return string(b), nil
		}
	}
	return "Daily routine not found", nil
}

type SetWeeklyBriefScheduleTool struct {
	routinesSvc *routines.Service
}

func (t *SetWeeklyBriefScheduleTool) Name() string { return "set_weekly_brief_schedule" }
func (t *SetWeeklyBriefScheduleTool) Description() string {
	return "Update the cron schedule or status for the weekly brief"
}
func (t *SetWeeklyBriefScheduleTool) Label() string { return "Gerenciando rotinas" }
func (t *SetWeeklyBriefScheduleTool) Summary(string) string { return "[SetWeeklyBriefScheduleTool executed successfully]" }

func (t *SetWeeklyBriefScheduleTool) SchemaJSON() string {
	return `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`
}
func (t *SetWeeklyBriefScheduleTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		CronExpr *string `json:"cron_expr"`
		Enabled  *bool   `json:"enabled"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	for _, r := range rs {
		if r.Type == "weekly" {
			updated, err := t.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
			if err != nil {
				return "", err
			}
			b, err := json.Marshal(updated)
			if err != nil {
				slog.Error("marshal updated weekly routine", "error", err)
				return "", err
			}
			return string(b), nil
		}
	}
	return "Weekly routine not found", nil
}
