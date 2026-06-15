package tools

import (
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/pkg/uid"
)

func parseArgs[T any](argsJSON string) (T, error) {
	var args T
	if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return args, fmt.Errorf("parse args: %w", err)
	}
	return args, nil
}

func formatID(id pgtype.UUID) string {
	return uid.UUIDToString(id)
}
