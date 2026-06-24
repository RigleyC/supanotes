# Spec: MCP Server Integration in SupaNotes

Introduce a Model Context Protocol (MCP) Server endpoint in the SupaNotes Go backend to expose Notes, Tasks, Memories, Tags, and Soul to external LLM clients (such as Claude Desktop, Cursor, or MCP Inspector) using Server-Sent Events (SSE).

## User Review Required

> [!IMPORTANT]
> The MCP server will be exposed as an HTTP/SSE endpoint at `/api/v1/mcp`.
> To connect local desktop clients (like Claude Desktop) to a remote/local HTTP/SSE server, you must configure the client with the required authentication header.
> Example `claude_desktop_config.json`:
> ```json
> {
>   "mcpServers": {
>     "supanotes": {
>       "command": "npx",
>       "args": ["-y", "@modelcontextprotocol/inspector", "http://localhost:8080/api/v1/mcp"],
>       "env": {
>         "HEADERS": "Authorization: Bearer <your-mcp-api-key>"
>       }
>     }
>   }
> }
> ```

## Proposed Changes

### Backend Component

#### [MODIFY] [go.mod](file:///c:/Users/rigleyc/projects/supanotes/backend/go.mod)
* Add the official MCP Go SDK dependency: `github.com/modelcontextprotocol/go-sdk`.

#### [NEW] [server.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/mcp/server.go)
* Initialize `mcp.Server` with the package implementation metadata.
* Set up the dependency injection for supanotes services (`NotesService`, `TasksService`, `MemoriesService`, `TagsService`, `SoulService`).
* Create helper function to extract user ID from standard `context.Context`.
* Build and configure the `mcp.NewStreamableHTTPHandler`.

#### [NEW] [middleware.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/mcp/middleware.go)
* Define the `MCPAuthMiddleware` that intercepts requests to `/api/v1/mcp/*`.
* Supports double-authentication flow:
  1. Extract and validate JWT bearer token using existing JWT secret configuration.
  2. If JWT is missing/invalid, check for static `MCP_API_KEY` (either in `Authorization: Bearer <key>` or `X-API-Key` headers).
  3. Resolve the static key to the user ID using the configured `MCP_USER_EMAIL` database lookup.
* If authenticated, inject the `pgtype.UUID` user ID into the HTTP request's `context.Context` using a private key type.

#### [NEW] [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/mcp/tools.go)
* Define tool argument structs with correct json tags and `jsonschema` documentation tags.
* Register tools with `mcp.AddTool`:
  * **Notes**: `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`.
  * **Tasks**: `list_tasks`, `create_task`, `update_task`, `complete_task`, `reopen_task`, `delete_task`.
  * **Memories**: `list_memories`, `create_memory`, `delete_memory`.
  * **Tags**: `list_tags`, `create_tag`, `add_tag_to_note`, `remove_tag_from_note`.
  * **Soul**: `get_soul`, `update_soul`.
* Inside each tool callback:
  1. Retrieve `user_id` from the request context.
  2. Map arguments, invoke the corresponding service, and format the output as `mcp.CallToolResult`.

#### [MODIFY] [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go)
* Initialize the MCP server and tools after initializing other backend services.
* Expose the endpoint by mounting the streamable HTTP handler to Echo:
  ```go
  mcpSrv := mcpapp.NewServer(cfg, queries, notesSvc, tasksSvc, memoriesSvc, tagsSvc, soulSvc)
  mcpHandler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
      return mrv
  }, nil)
  protectedMCP := api.Group("/mcp")
  protectedMCP.Use(mcpapp.Auth(cfg, queries))
  protectedMCP.Any("/*", echo.WrapHandler(http.StripPrefix("/api/v1/mcp", mcpHandler)))
  ```

#### [MODIFY] [.env.example](file:///c:/Users/rigleyc/projects/supanotes/backend/.env.example)
* Document the new configuration keys:
  ```bash
  # Model Context Protocol (MCP) Server configuration
  MCP_API_KEY=supanotes-local-mcp-secret-key-123
  MCP_USER_EMAIL=user@example.com
  ```

## Verification Plan

### Automated Tests
* Create unit tests in `backend/internal/mcp/middleware_test.go` to verify authentication (JWT and static API key routing/lookups).
* Create integration/unit tests for tools in `backend/internal/mcp/tools_test.go` using mock contexts.

### Manual Verification
* Run the backend server locally.
* Connect using the MCP inspector tool:
  `npx -y @modelcontextprotocol/inspector http://localhost:8080/api/v1/mcp`
  Passing the HTTP Header `Authorization: Bearer <key>`.
* Verify that notes, tasks, memories, tags, and soul can be read, searched, and updated successfully via the inspector UI.
