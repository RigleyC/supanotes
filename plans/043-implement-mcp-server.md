# Plan 043: Implement MCP Server Endpoint

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat c63cb0d..HEAD -- backend/go.mod backend/cmd/server/main.go backend/internal/mcp/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `c63cb0d`, 2026-06-24

## Why this matters

Exposing a Model Context Protocol (MCP) Server endpoint inside the SupaNotes backend enables external AI agents (like Claude Desktop or Cursor) to securely interact with the user's notes, tasks, memories, tags, and soul configuration. By running as an HTTP/SSE server that integrates with the standard JWT authentication, it automatically supports multiple users, keeping their data isolated, with zero database schema changes.

## Current state

The following files are relevant to this task:
- `backend/go.mod` — handles Go module dependencies.
- `backend/cmd/server/main.go` — registers server routes and starts the Echo web server.
- `backend/pkg/auth/jwt.go` — implements JWT generation and parsing helpers.
- `backend/internal/web/context.go` — contains user ID extraction helpers from Echo context.

Exemplar of routing and handlers registration in `backend/cmd/server/main.go` lines 166-174:
```go
	protected := api.Group("")
	protected.Use(auth.JWT(cfg))

	// Contexts
	ctxSvc := contexts.NewService(queries)
	ctxH := contexts.NewHandler(ctxSvc)
	protected.GET("/contexts", ctxH.List)
	protected.POST("/contexts", ctxH.Create)
	protected.DELETE("/contexts/:id", ctxH.Delete)
```

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
- `backend/internal/mcp/` (new directory containing `server.go`, `token.go`, `tools.go`, `token_test.go`, `tools_test.go`)

**Out of scope**:
- Modifications to existing service layers (`notes`, `tasks`, etc.) unless to fix a compilation bug or exposed interface mismatch.
- Modifying the Flutter client (settings page connection will be verified via API curls).

## Git workflow

- Branch: `feat/mcp-server`
- Commit per logical step; message style follows Conventional Commits, e.g.:
  - `feat(mcp): add go-sdk dependency and token handler`
  - `feat(mcp): register tools and implement server logic`
  - `feat(mcp): mount mcp route in main.go`

## Steps

### Step 1: Install MCP SDK
Add `github.com/modelcontextprotocol/go-sdk` to the Go module dependencies and tidy the module.
- Run: `go get github.com/modelcontextprotocol/go-sdk`
- Run: `go mod tidy` in the `backend` directory.

**Verify**: `go test ./...` and `make build` pass successfully.

### Step 2: Implement Token Generation Handler & Context Adapter
Create `backend/internal/mcp/token.go` to handle personal tokens and context propagation.
1. Implement `GenerateMCPTokenHandler(cfg *config.Config) echo.HandlerFunc`:
   * Extract the authenticated user's ID via `web.UserID(c)`.
   * Generate a long-lived JWT token (expires in 365 days) by calling `authpkg.GenerateAccessToken(uid.UUIDToString(userID), cfg.JWTSecret, 365*24*time.Hour)`.
   * Return a JSON response: `{"mcp_token": token}`.
2. Implement `PropagateUserContext(next http.Handler) echo.HandlerFunc`:
   * Extract the user's ID using `web.UserID(c)`.
   * Create a standard Go context containing the user ID: `ctx := context.WithValue(c.Request().Context(), userContextKey, userID)` (using private key type `contextKey`).
   * Update the request: `c.SetRequest(c.Request().WithContext(ctx))`.
   * Call `next.ServeHTTP(c.Response(), c.Request())`.
3. Implement the context helper:
   * `UserIDFromContext(ctx context.Context) (pgtype.UUID, error)` to retrieve the user's UUID from the standard context.

**Verify**: Write unit tests in `backend/internal/mcp/token_test.go` to verify:
- `GenerateMCPTokenHandler` generates a valid JWT with the correct expiration duration (approx. 365 days).
- `PropagateUserContext` successfully places the user ID from the Echo context into the HTTP request's context.
Run `go test ./internal/mcp` and ensure they pass.

### Step 3: Implement MCP Tools Registration
Create `backend/internal/mcp/tools.go` to define and register all the MCP tools.
- Implement registration for each tool under:
  - **Notes**: `list_notes`, `get_note`, `create_note`, `update_note`, `delete_note`.
  - **Tasks**: `list_tasks`, `create_task`, `update_task`, `complete_task`, `reopen_task`, `delete_task`.
  - **Memories**: `list_memories`, `create_memory`, `delete_memory`.
  - **Tags**: `list_tags`, `create_tag`, `add_tag_to_note`, `remove_tag_from_note`.
  - **Soul**: `get_soul`, `update_soul`.
- In each tool callback:
  1. Extract `user_id` using `UserIDFromContext(ctx)`.
  2. Invoke corresponding service methods (e.g., `notesSvc.List`, `tasksSvc.Create`).
  3. Format the result as `*mcp.CallToolResult`.

**Verify**: Write unit tests in `backend/internal/mcp/tools_test.go` to verify tool callback response logic and arguments mapping. Run `go test ./internal/mcp` and ensure all tests pass.

### Step 4: Implement Streamable HTTP Server & Mount Routes
Create `backend/internal/mcp/server.go` to expose the setup constructor:
- A constructor `NewServer(...) *mcp.Server` that initializes the server and registers all tools.
- Open `backend/cmd/server/main.go` and initialize the MCP server after other services have been initialized (around line 286).
- Wrap the handler using `mcp.NewStreamableHTTPHandler(func(req *http.Request) *mcp.Server { return mcpServer }, nil)`.
- Mount the handlers in `registerRoutes`:
  ```go
  // Personal Token Generation Route
  protected.POST("/auth/mcp-token", mcpapp.GenerateMCPTokenHandler(cfg))

  // MCP HTTP/SSE Route
  mcpWrapped := http.StripPrefix("/api/v1/mcp", mcpHandler)
  protected.Any("/mcp/*", mcpapp.PropagateUserContext(mcpWrapped))
  ```

**Verify**: Run `make build` and `make lint` to verify that everything compiles without errors or warnings.

## Test plan

- Unit tests:
  - `backend/internal/mcp/token_test.go` checking token generation and context propagation.
  - `backend/internal/mcp/tools_test.go` checking notes/tasks tool callbacks.
- Manual test:
  1. Start local Postgres container: `make dev-db-up`.
  2. Run migration: `make migrate-up`.
  3. Run backend server: `make run`.
  4. Perform login via API to get standard access token, then generate long-lived token:
     `curl -H "Authorization: Bearer <session-jwt>" -X POST http://localhost:8080/api/v1/auth/mcp-token`
  5. Use the MCP inspector tool using the generated token:
     `npx -y @modelcontextprotocol/inspector http://localhost:8080/api/v1/mcp`
     Configuring headers: `Authorization: Bearer <generated-mcp-token>`.
  6. Validate that calling `list_notes` or `list_tasks` yields the correct data in the inspector web UI.

## Done criteria

- [ ] `go test ./...` exits 0.
- [ ] `make build` compiles `bin/server` cleanly.
- [ ] New tests in `backend/internal/mcp/` verify all components and pass.
- [ ] No files outside the in-scope list are modified (`git status`).
- [ ] `plans/README.md` status row updated.

## STOP conditions

- The Go compiler version fails to compile or resolve `github.com/modelcontextprotocol/go-sdk` packages.
- A step's verification fails twice after reasonable fix attempt.
- The fix appears to require modifying out-of-scope files.

## Maintenance notes

- If services interfaces change, the tool callbacks in `backend/internal/mcp/tools.go` must be updated.
- Personal access tokens must be stored securely by the client and not checked into git.
