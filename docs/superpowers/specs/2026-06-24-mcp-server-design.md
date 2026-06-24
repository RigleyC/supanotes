# Spec: MCP Server Integration in SupaNotes

Introduce a Model Context Protocol (MCP) Server endpoint in the SupaNotes Go backend to expose Notes, Tasks, Memories, Tags, and Soul to external LLM clients (such as Claude Desktop, Cursor, or MCP Inspector) using Server-Sent Events (SSE).

## User Review Required

> [!IMPORTANT]
> The MCP server will be exposed as an HTTP/SSE endpoint at `/api/v1/mcp`.
> To connect local desktop clients (like Claude Desktop or Cursor) to the server, you will generate a long-lived Personal Access Token (PAT) from the application settings page and configure it as an Authorization header.
> Example `claude_desktop_config.json`:
> ```json
> {
>   "mcpServers": {
>     "supanotes": {
>       "command": "npx",
>       "args": ["-y", "@modelcontextprotocol/inspector", "http://localhost:8080/api/v1/mcp"],
>       "env": {
>         "HEADERS": "Authorization: Bearer <your-generated-personal-mcp-token>"
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
* Create a helper function `UserIDFromContext(ctx context.Context) (pgtype.UUID, error)` to retrieve the authenticated user ID inside MCP tool callbacks.
* Build and configure the `mcp.NewStreamableHTTPHandler`.

#### [NEW] [token.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/mcp/token.go)
* Define the Echo handler `GenerateMCPTokenHandler(cfg *config.Config)` registered under `POST /api/v1/auth/mcp-token`.
* Generate a long-lived JWT token with a 365-day expiry duration using `authpkg.GenerateAccessToken(userID, cfg.JWTSecret, 365*24*time.Hour)`.
* Define an Echo-to-stdlib adapter `PropagateUserContext(next http.Handler)` that extracts the user ID from the Echo context (set by `auth.JWT`) and places it into the standard Go context of the HTTP request, then serves the request.

#### [NEW] [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/mcp/tools.go)
* Define tool argument structs with correct JSON tags and `jsonschema` documentation tags.
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
* Expose the endpoint by mounting the token endpoint and the streamable HTTP handler to Echo:
  ```go
  // Register Personal Access Token generation route
  protected.POST("/auth/mcp-token", mcpapp.GenerateMCPTokenHandler(cfg))

  // Register MCP HTTP/SSE endpoints
  mcpSrv := mcpapp.NewServer(cfg, queries, notesSvc, tasksSvc, memoriesSvc, tagsSvc, soulSvc)
  mcpHandler := mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server {
      return mcpSrv
  }, nil)
  
  mcpWrapped := http.StripPrefix("/api/v1/mcp", mcpHandler)
  protected.Any("/mcp/*", mcpapp.PropagateUserContext(mcpWrapped))
  ```

## Verification Plan

### Automated Tests
* Create unit tests in `backend/internal/mcp/token_test.go` to verify token generation.
* Create integration/unit tests for tools in `backend/internal/mcp/tools_test.go` using mock contexts.

### Manual Verification
* Run the backend server locally.
* Generate a token using the new endpoint:
  `curl -H "Authorization: Bearer <session-jwt>" -X POST http://localhost:8080/api/v1/auth/mcp-token`
* Connect using the MCP inspector tool:
  `npx -y @modelcontextprotocol/inspector http://localhost:8080/api/v1/mcp`
  Passing the HTTP Header `Authorization: Bearer <generated-token>`.
* Verify that notes, tasks, memories, tags, and soul can be read, searched, and updated successfully via the inspector UI.
