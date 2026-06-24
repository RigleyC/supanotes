# Plan 043: Implement MCP Server Endpoint

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 54db378..HEAD -- backend/go.mod backend/cmd/server/main.go backend/internal/mcp/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `54db378`, 2026-06-24

## Why this matters

Exposing a Model Context Protocol (MCP) Server endpoint inside the SupaNotes backend enables external AI agents (like Claude Desktop or Cursor) to securely interact with the user's notes, tasks, memories, tags, and soul configuration. By running as an HTTP/SSE server, it reuses the existing backend database connection, services, and authentication, making it clean and easy to configure locally.

## Current state

The following files are relevant to this task:
- `backend/go.mod` — handles Go module dependencies.
- `backend/cmd/server/main.go` — registers server routes and starts the Echo web server.
- `backend/internal/auth/middleware.go` — implements existing JWT authentication middleware.
- `backend/internal/web/context.go` — contains user ID extraction helpers from Echo context.

Existing exemplar for service dependencies in `backend/cmd/server/main.go` lines 270-293:
```go
	// Routines
	routinesRepo := routines.NewRepository(queries)
	routinesSvc := routines.NewService(routinesRepo, agentCtxBldr, llmFactory)
...
	// Agent Loop
	agentRepo := agent.NewRepository(queries)
	agentTools := agent.NewToolRegistry(queries, notesSvc, tasksSvc, memoriesSvc, routinesSvc, soulSvc, embeddingClient, llmFactory)
	agentLoop := agent.NewLoop(agentRepo, llmFactory, agentCtxBldr, agentTools)
```

We will need to initialize our new MCP server package and pass the required services:
- `notesSvc` (notes)
- `tasksSvc` (tasks)
- `memoriesSvc` (memories)
- `tagsSvc` (tags)
- `soulSvc` (soul)

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Install   | `go get github.com/modelcontextprotocol/go-sdk` | exit 0, updates go.mod |
| Tidy      | `make tidy`              | exit 0              |
| Compile   | `make build`             | exit 0, compiles bin/server |
| Lint      | `make lint`              | exit 0, no vet issues |
| Tests     | `make test`              | all tests pass      |

## Scope

**In scope**:
- `backend/go.mod`
- `backend/go.sum`
- `backend/cmd/server/main.go`
- `backend/internal/mcp/` (new directory containing `server.go`, `middleware.go`, `tools.go`, `middleware_test.go`, `tools_test.go`)
- `backend/.env.example`

**Out of scope**:
- Modifications to existing service layers (`notes`, `tasks`, etc.) unless to fix a compilation bug or exposed interface mismatch.
- Modifying the Flutter client.

## Git workflow

- Branch: `feat/mcp-server`
- Commit per logical step; message style follows Conventional Commits, e.g.:
  - `feat(mcp): add go-sdk dependency and setup middleware`
  - `feat(mcp): register tools and implement server logic`
  - `feat(mcp): mount mcp route in main.go`

## Steps

### Step 1: Install MCP SDK and Add Configuration
Add `github.com/modelcontextprotocol/go-sdk` to the Go module dependencies, run `go mod tidy`, and update `.env.example`.
- Run: `go get github.com/modelcontextprotocol/go-sdk`
- Run: `go mod tidy` in the `backend` directory.
- Update `backend/.env.example` to document the new settings:
  ```bash
  # Model Context Protocol (MCP) Server configuration
  MCP_API_KEY=supanotes-local-mcp-secret-key-123
  MCP_USER_EMAIL=user@example.com
  ```
**Verify**: `go test ./...` and `make build` pass successfully.

### Step 2: Implement MCP Authentication Middleware
Create `backend/internal/mcp/middleware.go` containing `MCPAuthMiddleware`.
This middleware must check for:
1. Standard `Authorization: Bearer <jwt-token>` header. Parse the access token using `authpkg.ParseAccessToken(token, cfg.JWTSecret)`.
2. Static key check: If JWT is missing/invalid, check if the header matches `MCP_API_KEY` (either in `Authorization: Bearer <static-key>` or `X-API-Key`).
3. If the static key matches, lookup the user using `queries.GetUserByEmail(ctx, cfg.MCPUserEmail)`.
4. Store the retrieved `pgtype.UUID` user ID inside the request context using a custom private key type `contextKey` (e.g. `const userContextKey contextKey = "mcp_user_id"`).
5. Expose a helper `UserIDFromContext(ctx context.Context) (pgtype.UUID, error)` to retrieve the ID within MCP tool callbacks.

**Verify**: Write a simple unit test in `backend/internal/mcp/middleware_test.go` with mock requests, validating:
- Valid JWT token successfully authenticates and stores the user ID.
- Valid Static API key successfully authenticates, resolves user via email, and stores the user ID.
- Missing/invalid keys return `401 Unauthorized` or standard Echo error.
Run `go test ./internal/mcp` and ensure it passes.

### Step 3: Implement MCP Tools Registration
Create `backend/internal/mcp/tools.go` to define and register the MCP tools.
- Implement registration for each tool under:
  - **Notes**: `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`.
  - **Tasks**: `list_tasks`, `create_task`, `update_task`, `complete_task`, `reopen_task`, `delete_task`.
  - **Memories**: `list_memories`, `create_memory`, `delete_memory`.
  - **Tags**: `list_tags`, `create_tag`, `add_tag_to_note`, `remove_tag_from_note`.
  - **Soul**: `get_soul`, `update_soul`.
- In each tool handler:
  1. Extract `user_id` using `UserIDFromContext(ctx)`.
  2. Invoke corresponding service methods (e.g., `notesSvc.List`, `tasksSvc.Create`).
  3. Format the result as `*mcp.CallToolResult`.

**Verify**: Write unit tests in `backend/internal/mcp/tools_test.go` to verify schema generation and callback logic for notes/tasks tools. Run `go test ./internal/mcp` and ensure all tests pass.

### Step 4: Implement Streamable HTTP Server & Mount Routes
Create `backend/internal/mcp/server.go` to expose the setup constructor:
- A constructor `NewServer(...) *mcp.Server` that initializes the server and registers all tools.
- Open `backend/cmd/server/main.go` and initialize the MCP server after other services have been initialized (around line 286).
- Wrap the handler using `mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server { return mcpServer }, nil)`.
- Mount the handler in `registerRoutes`:
  ```go
  mcpGroup := api.Group("/mcp")
  mcpGroup.Use(mcpapp.Auth(cfg, queries))
  mcpGroup.Any("/*", echo.WrapHandler(http.StripPrefix("/api/v1/mcp", mcpHandler)))
  ```
**Verify**: Run `make build` and `make lint` to verify that everything compiles without errors or warnings.

## Test plan

- Unit tests:
  - `backend/internal/mcp/middleware_test.go` checking all auth cases (JWT, Static API key lookup, Unauthorized).
  - `backend/internal/mcp/tools_test.go` checking note listing/creation mock invocations.
- Manual test:
  1. Start local Postgres container: `make dev-db-up`.
  2. Run migration: `make migrate-up`.
  3. Run backend server: `make run`.
  4. Use the MCP inspector tool:
     `npx -y @modelcontextprotocol/inspector http://localhost:8080/api/v1/mcp`
     Configuring headers: `Authorization: Bearer <static-key>`.
  5. Validate that calling `list_notes` or `list_tasks` yields the correct data in the inspector web UI.

## Done criteria

- [ ] `go test ./...` exits 0.
- [ ] `make build` compiles `bin/server` cleanly.
- [ ] New tests in `backend/internal/mcp/` verify middleware and tools and all pass.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row updated.

## STOP conditions

- The Go compiler version fails to compile or resolve `github.com/modelcontextprotocol/go-sdk` packages.
- A step's verification fails twice after reasonable fix attempt.
- The fix appears to require modifying out-of-scope files.

## Maintenance notes

- If services interfaces (like `notesSvc` or `tasksSvc`) change, the tool callbacks in `backend/internal/mcp/tools.go` must be updated.
- Secure the static `MCP_API_KEY` by never committing it to version control.
