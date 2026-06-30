package tools

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type UpdateProfileArgs struct {
	Profile map[string]any `json:"profile"`
}

type UpdateUserProfileTool struct {
	q sqlcgen.Querier
}

func (t *UpdateUserProfileTool) Name() string { return "update_user_profile" }
func (t *UpdateUserProfileTool) Description() string {
	return "Update stable user preferences and profile information (JSON object)"
}
func (t *UpdateUserProfileTool) SchemaJSON() string {
	return `{"type":"object","properties":{"profile":{"type":"object"}},"required":["profile"]}`
}
func (t *UpdateUserProfileTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	var args UpdateProfileArgs
	if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return "", fmt.Errorf("update_user_profile: parse args: %w", err)
	}
	profileBytes, err := json.Marshal(args.Profile)
	if err != nil {
		return "", fmt.Errorf("update_user_profile: marshal profile: %w", err)
	}
	_, err = t.q.UpdateSoulProfile(ctx, sqlcgen.UpdateSoulProfileParams{
		UserID:  userID,
		Profile: profileBytes,
	})
	if err != nil {
		return "", fmt.Errorf("update_user_profile: %w", err)
	}
	return "User profile updated successfully.", nil
}
