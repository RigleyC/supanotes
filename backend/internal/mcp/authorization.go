package mcpapp

import (
	"context"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const (
	mcpMethodListTools = "tools/list"
	mcpMethodCallTool  = "tools/call"
)

func requiredToolScope(name string) string {
	if toolRequiresWrite(name) {
		return "write"
	}
	return "read"
}

func requireToolScope(ctx context.Context, name string) error {
	scope := requiredToolScope(name)
	if !HasScope(ctx, scope) {
		return fmt.Errorf("MCP token lacks %s scope", scope)
	}
	return nil
}

// scopeMiddleware applies authorization at the protocol boundary. Filtering
// discovery is important because a hidden write tool must also be rejected if
// a client calls it directly without first listing tools.
func scopeMiddleware(next mcp.MethodHandler) mcp.MethodHandler {
	return func(ctx context.Context, method string, request mcp.Request) (mcp.Result, error) {
		switch method {
		case mcpMethodListTools:
			result, err := next(ctx, method, request)
			if err != nil {
				return nil, err
			}
			list, ok := result.(*mcp.ListToolsResult)
			if !ok {
				return result, nil
			}
			filtered := make([]*mcp.Tool, 0, len(list.Tools))
			for _, tool := range list.Tools {
				if tool != nil && HasScope(ctx, requiredToolScope(tool.Name)) {
					filtered = append(filtered, tool)
				}
			}
			copy := *list
			copy.Tools = filtered
			// The SDK paginates before this middleware. The current registry is
			// intentionally kept below the SDK page size, so a filtered page is
			// complete and must not expose a cursor for hidden tools.
			copy.NextCursor = ""
			return &copy, nil
		case mcpMethodCallTool:
			call, ok := request.(*mcp.ServerRequest[*mcp.CallToolParamsRaw])
			if ok && call.Params != nil {
				if err := requireToolScope(ctx, call.Params.Name); err != nil {
					return asError(err)
				}
			}
		}
		return next(ctx, method, request)
	}
}
