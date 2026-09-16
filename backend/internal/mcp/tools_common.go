package mcpapp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/pkg/uid"
)

func addTool(server *mcp.Server, security SecurityStore, tool *mcp.Tool, handler mcp.ToolHandler) {
	if security == nil {
		panic("MCP security dependency is required")
	}
	server.AddTool(tool, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if err := requireToolScope(ctx, tool.Name); err != nil {
			return asError(err)
		}
		userID, userErr := UserIDFromContext(ctx)
		if userErr != nil {
			return asError(userErr)
		}
		resource, resourceErr := resourceFromRequest(request)
		if resourceErr != nil {
			return asError(resourceErr)
		}
		startEvent := AuditEvent{
			TokenID:  TokenIDFromContext(ctx),
			UserID:   userID,
			Agent:    agentFromRequest(request),
			ToolName: tool.Name,
			Resource: resource,
			Result:   "started",
		}
		if auditErr := security.Audit(ctx, startEvent); auditErr != nil {
			return asError(fmt.Errorf("MCP audit failed before tool execution: %w", auditErr))
		}
		result, err := handler(ctx, request)
		status := "success"
		if err != nil {
			status = "error"
		} else if result != nil && result.IsError {
			status = "tool_error"
		}
		if auditErr := security.Audit(ctx, AuditEvent{
			TokenID:  startEvent.TokenID,
			UserID:   startEvent.UserID,
			Agent:    startEvent.Agent,
			ToolName: startEvent.ToolName,
			Resource: startEvent.Resource,
			Result:   status,
		}); auditErr != nil {
			if result == nil {
				result = &mcp.CallToolResult{}
			}
			result.Content = append(result.Content, &mcp.TextContent{Text: "MCP audit warning: final audit was not recorded"})
		}
		return result, err
	})
}

func agentFromRequest(request *mcp.CallToolRequest) string {
	if request != nil {
		if session, ok := request.GetSession().(*mcp.ServerSession); ok {
			if params := session.InitializeParams(); params != nil && params.ClientInfo != nil {
				if params.ClientInfo.Version == "" {
					return safeLogValue(params.ClientInfo.Name)
				}
				return safeLogValue(params.ClientInfo.Name) + "/" + safeLogValue(params.ClientInfo.Version)
			}
		}
	}
	return "unknown-agent"
}

func resourceFromRequest(request *mcp.CallToolRequest) (string, error) {
	args, err := rawArgumentMap(request)
	if err != nil {
		return "", err
	}
	if _, ok := args["note_id"]; ok {
		if _, ok := args["user_id"]; ok {
			return "note/user", nil
		}
		return "note", nil
	}
	for _, key := range []string{"note_id", "block_id", "attachment_id", "id", "user_id"} {
		if _, ok := args[key]; ok {
			return key, nil
		}
	}
	return "", nil
}

func confirmationArguments(request *mcp.CallToolRequest) (json.RawMessage, error) {
	args, err := rawArgumentMap(request)
	if err != nil {
		return nil, err
	}
	delete(args, "confirmation_id")
	encoded, err := json.Marshal(args)
	if err != nil {
		return nil, errors.New("invalid confirmation arguments")
	}
	return encoded, nil
}

func requireConfirmation(ctx context.Context, security SecurityStore, request *mcp.CallToolRequest, toolName, resource string) (ConfirmationLease, error) {
	if security == nil {
		return nil, errors.New("MCP security store is not configured")
	}
	userID, err := UserIDFromContext(ctx)
	if err != nil {
		return nil, err
	}
	args, err := rawArgumentMap(request)
	if err != nil {
		return nil, err
	}
	var confirmationID string
	if rawID, ok := args["confirmation_id"]; ok {
		if err := json.Unmarshal(rawID, &confirmationID); err != nil {
			return nil, errors.New("confirmation_id must be a UUID")
		}
	}
	confirmationID = strings.TrimSpace(confirmationID)
	arguments, err := confirmationArguments(request)
	if err != nil {
		return nil, err
	}
	if confirmationID == "" {
		confirmation, createErr := security.CreateConfirmation(ctx, userID, toolName, resource, arguments)
		if createErr != nil {
			return nil, fmt.Errorf("failed to create MCP confirmation: %w", createErr)
		}
		return nil, fmt.Errorf(`{"confirmation_required":true,"confirmation_id":%q,"expires_at":%q}`, confirmation.ID.String(), confirmation.ExpiresAt.UTC().Format(time.RFC3339))
	}
	id, err := uid.UUIDFromString(confirmationID)
	if err != nil {
		return nil, ErrConfirmationDenied
	}
	return security.ReserveConfirmation(ctx, userID, id, toolName, resource, arguments)
}

func replayConfirmation(lease ConfirmationLease) (*mcp.CallToolResult, bool, error) {
	if lease == nil {
		return nil, false, nil
	}
	payload, ok := lease.ReplayResult()
	if !ok {
		return nil, false, nil
	}
	if !json.Valid(payload) {
		return nil, false, errors.New("MCP confirmation replay result is invalid")
	}
	return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: string(payload)}}}, true, nil
}

func finishConfirmation(ctx context.Context, lease ConfirmationLease, result any, operationErr error) error {
	if lease == nil {
		return operationErr
	}
	if operationErr != nil {
		// The mutation may have reached its owner before returning an error or
		// before the process crashed. Keep the confirmation pending so a retry
		// cannot execute an effect a second time. Explicit Release is reserved
		// for callers that know no mutation was attempted.
		return operationErr
	}
	payload, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("failed to persist MCP confirmation result: %w", err)
	}
	return lease.Commit(ctx, payload)
}

func finishConfirmationMutation(ctx context.Context, lease ConfirmationLease, mutation ConfirmationMutation) (json.RawMessage, error) {
	if lease == nil {
		return nil, errors.New("MCP confirmation lease is missing")
	}
	return lease.CommitMutation(ctx, mutation)
}

func asTextResult(v any) (*mcp.CallToolResult, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return asError(fmt.Errorf("failed to encode MCP result: %w", err))
	}
	return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: string(b)}}}, nil
}

func asTextResultWithWarning(v any, warning error) (*mcp.CallToolResult, error) {
	result, err := asTextResult(v)
	if err != nil || warning == nil {
		return result, err
	}
	result.Content = append(result.Content, &mcp.TextContent{Text: "MCP confirmation warning: finalization failed; retry may be required"})
	return result, nil
}

func asError(err error) (*mcp.CallToolResult, error) {
	return &mcp.CallToolResult{
		IsError: true,
		Content: []mcp.Content{&mcp.TextContent{Text: err.Error()}},
	}, nil
}

func rawArgumentMap(req *mcp.CallToolRequest) (map[string]json.RawMessage, error) {
	if req == nil || req.Params == nil {
		return nil, errors.New("MCP tool arguments are missing")
	}
	var m map[string]json.RawMessage
	raw := bytes.TrimSpace(req.Params.Arguments)
	if len(raw) == 0 {
		return map[string]json.RawMessage{}, nil
	}
	if raw[0] != '{' {
		return nil, errors.New("MCP tool arguments must be a JSON object")
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, fmt.Errorf("invalid MCP tool arguments: %w", err)
	}
	if m == nil {
		return nil, errors.New("MCP tool arguments must be a JSON object")
	}
	return m, nil
}

func decodeToolArgs[T any](req *mcp.CallToolRequest) (T, error) {
	var args T
	if req == nil || req.Params == nil {
		return args, errors.New("MCP tool arguments are missing")
	}
	raw := bytes.TrimSpace(req.Params.Arguments)
	if len(raw) == 0 {
		raw = []byte("{}")
	}
	if raw[0] != '{' {
		return args, errors.New("MCP tool arguments must be a JSON object")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&args); err != nil {
		return args, fmt.Errorf("invalid MCP tool arguments: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return args, errors.New("invalid MCP tool arguments: multiple JSON values")
		}
		return args, fmt.Errorf("invalid MCP tool arguments: %w", err)
	}
	return args, nil
}

func objectPayload(payload json.RawMessage) (json.RawMessage, error) {
	if len(bytes.TrimSpace(payload)) == 0 {
		return json.RawMessage(`{}`), nil
	}
	trimmed := bytes.TrimSpace(payload)
	if trimmed[0] != '{' {
		return nil, errors.New("payload must be a JSON object")
	}
	var value map[string]any
	if err := json.Unmarshal(trimmed, &value); err != nil {
		return nil, fmt.Errorf("invalid payload: %w", err)
	}
	return json.RawMessage(trimmed), nil
}

func safeLogValue(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "unknown"
	}
	for _, r := range value {
		if r < 0x20 || r == 0x7f || strings.ContainsRune("/?#&=", r) {
			return "redacted"
		}
	}
	if len(value) > 128 {
		return "redacted"
	}
	return value
}

func optionalToolTime(value, name string) (*time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, fmt.Errorf("%s must be RFC3339", name)
	}
	return &parsed, nil
}
