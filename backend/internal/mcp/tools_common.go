package mcpapp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/pkg/uid"
)

func addTool(server *mcp.Server, security SecurityStore, tool *mcp.Tool, handler mcp.ToolHandler) {
	if security == nil {
		panic("MCP security dependency is required")
	}
	server.AddTool(tool, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
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
			status = "error: " + err.Error()
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
			result.Content = append(result.Content, &mcp.TextContent{Text: "MCP audit warning: " + auditErr.Error()})
		}
		return result, err
	})
}

func agentFromRequest(request *mcp.CallToolRequest) string {
	if request != nil {
		if session, ok := request.GetSession().(*mcp.ServerSession); ok {
			if params := session.InitializeParams(); params != nil && params.ClientInfo != nil {
				if params.ClientInfo.Version == "" {
					return params.ClientInfo.Name
				}
				return params.ClientInfo.Name + "/" + params.ClientInfo.Version
			}
		}
	}
	return "unknown-agent"
}

func resourceFromRequest(request *mcp.CallToolRequest) (string, error) {
	args, err := parseArgs(request)
	if err != nil {
		return "", err
	}
	if noteID := getStr(args, "note_id"); noteID != "" {
		if userID := getStr(args, "user_id"); userID != "" {
			return "note:" + noteID + "/user:" + userID, nil
		}
		return "note:" + noteID, nil
	}
	for _, key := range []string{"note_id", "block_id", "attachment_id", "id", "user_id"} {
		if value := getStr(args, key); value != "" {
			return key + ":" + value, nil
		}
	}
	return "", nil
}

func confirmationArguments(request *mcp.CallToolRequest) (json.RawMessage, error) {
	args, err := parseArgs(request)
	if err != nil {
		return nil, err
	}
	delete(args, "confirmation_id")
	encoded, err := json.Marshal(args)
	if err != nil {
		return nil, fmt.Errorf("invalid confirmation arguments: %w", err)
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
	args, err := parseArgs(request)
	if err != nil {
		return nil, err
	}
	confirmationID := getStr(args, "confirmation_id")
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

func finishConfirmation(ctx context.Context, lease ConfirmationLease, operationErr error) error {
	if lease == nil {
		return operationErr
	}
	if operationErr != nil {
		if releaseErr := lease.Release(ctx); releaseErr != nil {
			return errors.Join(operationErr, fmt.Errorf("failed to release MCP confirmation: %w", releaseErr))
		}
		return operationErr
	}
	return lease.Commit(ctx)
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
	result.Content = append(result.Content, &mcp.TextContent{Text: "MCP confirmation warning: " + warning.Error()})
	return result, nil
}

func asError(err error) (*mcp.CallToolResult, error) {
	return &mcp.CallToolResult{
		IsError: true,
		Content: []mcp.Content{&mcp.TextContent{Text: err.Error()}},
	}, nil
}

func parseArgs(req *mcp.CallToolRequest) (map[string]any, error) {
	if req == nil || req.Params == nil {
		return nil, errors.New("MCP tool arguments are missing")
	}
	var m map[string]any
	if len(req.Params.Arguments) == 0 {
		return map[string]any{}, nil
	}
	if err := json.Unmarshal(req.Params.Arguments, &m); err != nil {
		return nil, fmt.Errorf("invalid MCP tool arguments: %w", err)
	}
	if m == nil {
		return nil, errors.New("MCP tool arguments must be a JSON object")
	}
	return m, nil
}

func getStr(args map[string]any, key string) string {
	if v, ok := args[key].(string); ok {
		return v
	}
	return ""
}

func getInt(args map[string]any, key string, fallback int32) int32 {
	if value, ok := args[key].(float64); ok {
		return int32(value)
	}
	return fallback
}

func getUUID(args map[string]any, key string) (pgtype.UUID, error) {
	id := getStr(args, key)
	if id == "" {
		return pgtype.UUID{}, fmt.Errorf("%s is required", key)
	}
	return uid.UUIDFromString(id)
}

func getOptionalTime(args map[string]any, key string) (*time.Time, error) {
	value := getStr(args, key)
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, fmt.Errorf("%s must be RFC3339: %w", key, err)
	}
	return &parsed, nil
}

func operationPayload(args map[string]any) (json.RawMessage, error) {
	payload, ok := args["payload"]
	if !ok {
		return json.RawMessage(`{}`), nil
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("invalid payload: %w", err)
	}
	return encoded, nil
}
