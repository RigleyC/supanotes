import re

with open('internal/agent/tools.go', 'r') as f:
    content = f.read()

# Replace struct definition
content = content.replace('memoriesSvc *memories.Service\n}', 'memoriesSvc *memories.Service\n\troutinesSvc *routines.Service\n}')

# Add import
content = content.replace('"github.com/RigleyC/supanotes/internal/tasks"', '"github.com/RigleyC/supanotes/internal/tasks"\n\t"github.com/RigleyC/supanotes/internal/routines"')

# Update constructor
content = content.replace('func NewToolRegistry(q sqlcgen.Querier, notesSvc *notes.Service, tasksSvc *tasks.Service, memoriesSvc *memories.Service) *ToolRegistry {', 'func NewToolRegistry(q sqlcgen.Querier, notesSvc *notes.Service, tasksSvc *tasks.Service, memoriesSvc *memories.Service, routinesSvc *routines.Service) *ToolRegistry {')
content = content.replace('memoriesSvc: memoriesSvc,\n\t}', 'memoriesSvc: memoriesSvc,\n\t\troutinesSvc: routinesSvc,\n\t}')

# Add tool schemas
schemas = """		{
			Name:        "set_daily_brief_schedule",
			Description: "Update the cron schedule or status for the daily brief",
			SchemaJSON:  `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`,
		},
		{
			Name:        "set_weekly_brief_schedule",
			Description: "Update the cron schedule or status for the weekly brief",
			SchemaJSON:  `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`,
		},
"""
content = content.replace('Name:        "test_weekly_brief",', schemas + 'Name:        "test_weekly_brief",')

# Add switch cases
cases = """	case "list_routines":
		rs, err := tr.routinesSvc.GetRoutines(ctx, userID)
		if err != nil {
			return "", err
		}
		b, _ := json.Marshal(rs)
		return string(b), nil
	case "test_daily_brief":
		resp, err := tr.routinesSvc.TestRoutine(ctx, userID, "daily")
		if err != nil {
			return "", err
		}
		return resp, nil
	case "test_weekly_brief":
		resp, err := tr.routinesSvc.TestRoutine(ctx, userID, "weekly")
		if err != nil {
			return "", err
		}
		return resp, nil
	case "set_daily_brief_schedule":
		var args struct {
			CronExpr *string `json:"cron_expr"`
			Enabled  *bool   `json:"enabled"`
		}
		if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
			return "", err
		}
		// Fetch existing to get ID
		rs, err := tr.routinesSvc.GetRoutines(ctx, userID)
		if err != nil { return "", err }
		for _, r := range rs {
			if r.Type == "daily" {
				updated, err := tr.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
				if err != nil { return "", err }
				b, _ := json.Marshal(updated)
				return string(b), nil
			}
		}
		return "Daily routine not found", nil
	case "set_weekly_brief_schedule":
		var args struct {
			CronExpr *string `json:"cron_expr"`
			Enabled  *bool   `json:"enabled"`
		}
		if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
			return "", err
		}
		rs, err := tr.routinesSvc.GetRoutines(ctx, userID)
		if err != nil { return "", err }
		for _, r := range rs {
			if r.Type == "weekly" {
				updated, err := tr.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
				if err != nil { return "", err }
				b, _ := json.Marshal(updated)
				return string(b), nil
			}
		}
		return "Weekly routine not found", nil
"""
# Find default case
idx = content.rfind('default:')
content = content[:idx] + cases + content[idx:]

with open('internal/agent/tools.go', 'w') as f:
    f.write(content)
