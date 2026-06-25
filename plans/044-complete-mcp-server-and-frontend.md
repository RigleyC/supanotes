# Plan 044: Complete MCP Server and Frontend Settings UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the backend MCP server by defining precise tool schemas and robust unit tests, and build the frontend Flutter UI settings screen for token generation and client configuration.

**Architecture:** Extend the backend tools registration in `backend/internal/mcp/tools.go` with JSON schemas, write mock-based unit tests in Go, extend the settings HTTP repository in Flutter, register GoRouter navigation routes, and design the `McpScreen` in Flutter.

**Tech Stack:** Go (mcp sdk, echo), Flutter (riverpod, go_router, super_editor).

---

## Scope

**In scope:**
- `backend/internal/mcp/tools.go`
- `backend/internal/mcp/tools_test.go`
- `lib/features/settings/data/settings_repository.dart`
- `lib/core/router/app_routes.dart`
- `lib/core/router/app_router.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/settings/presentation/mcp_screen.dart` [NEW]

---

### Task 1: Complete Backend Tool Schemas

Define precise JSON schemas for all MCP tools instead of using `emptySchema`.

**Files:**
- Modify: `backend/internal/mcp/tools.go`

- [ ] **Step 1: Replace emptySchema with structured schemas**
  - Open `backend/internal/mcp/tools.go`.
  - Define schemas for notes, tasks, memories, tags, and soul tools.
  - Examples:
    ```go
    idParam := map[string]any{
        "id": map[string]any{
            "type": "string",
            "description": "The UUID of the item",
        },
    }
    requiredId := []string{"id"}

    getNoteSchema := map[string]any{
        "type": "object",
        "properties": idParam,
        "required": requiredId,
    }
    createNoteSchema := map[string]any{
        "type": "object",
        "properties": map[string]any{
            "content": map[string]any{
                "type": "string",
                "description": "The text content of the note",
            },
        },
        "required": []string{"content"},
    }
    ```
  - Map schemas to the respective `mcp.Tool.InputSchema` properties in `RegisterTools`.
- [ ] **Step 2: Verify compilation**
  - Run: `make build` in the `backend` directory.
  - Expected: Clean compilation.
- [ ] **Step 3: Commit**
  - Run: `git commit -am "feat(mcp): add detailed JSON schemas to mcp tools"`

---

### Task 2: Implement Backend Unit Tests for MCP Tools

Write unit tests for the tool execution callbacks in `tools_test.go` utilizing service mock interfaces.

**Files:**
- Modify: `backend/internal/mcp/tools_test.go`

- [ ] **Step 1: Set up mocks and test tool execution**
  - Define mock implementations or test cases for the notes, tasks, and memories services.
  - Implement tests verifying:
    - Successful call to `get_note` maps the UUID correctly.
    - Error handling when calling `get_note` with an invalid UUID.
    - Successful call to `create_note` parses the `content` argument.
    - Successful call to task tools (`create_task`, `complete_task`) maps title/ID.
- [ ] **Step 2: Run backend tests**
  - Run: `go test -v ./internal/mcp` in `backend` directory.
  - Expected: PASS
- [ ] **Step 3: Commit**
  - Run: `git commit -am "test(mcp): add unit tests for tools arguments mapping"`

---

### Task 3: Extend Frontend Settings Repository

Extend `ISettingsRepository` to add the `POST /auth/mcp-token` endpoint handler.

**Files:**
- Modify: `lib/features/settings/data/settings_repository.dart`

- [ ] **Step 1: Declare generateMcpToken in repository**
  - Open `lib/features/settings/data/settings_repository.dart`.
  - Add `Future<String> generateMcpToken();` to `ISettingsRepository`.
  - Implement it in `SettingsRepository`:
    ```dart
    @override
    Future<String> generateMcpToken() async {
      try {
        final response = await _api.post<Map<String, dynamic>>('/auth/mcp-token');
        final body = response.data;
        if (body == null || !body.containsKey('mcp_token')) {
          throw const ServerException(
            message: 'Resposta inválida do servidor',
            statusCode: 500,
          );
        }
        return body['mcp_token'] as String;
      } on DioException catch (e) {
        throw fromDioError(e);
      }
    }
    ```
- [ ] **Step 2: Verify project builds**
  - Run: `flutter analyze` or compile.
  - Expected: Clean analyzer check.
- [ ] **Step 3: Commit**
  - Run: `git commit -am "feat(settings): add generateMcpToken endpoint to repository"`

---

### Task 4: Flutter Route Registration & McpScreen UI

Create the MCP configuration screen and add a settings tile to navigate to it.

**Files:**
- Modify: `lib/core/router/app_routes.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Create: `lib/features/settings/presentation/mcp_screen.dart`

- [ ] **Step 1: Add Route Constants and GoRouter Route**
  - Open `lib/core/router/app_routes.dart` and add `static const mcp = '/settings/mcp';`.
  - Open `lib/core/router/app_router.dart` and register `McpScreen` under `AppRoutes.mcp`.
- [ ] **Step 2: Create McpScreen Widget**
  - Implement `McpScreen` in `lib/features/settings/presentation/mcp_screen.dart`.
  - Use the project's standard page structure: `CustomScrollView`, `SliverAppBar.medium(title: const Text('Model Context Protocol (MCP)'))`, and `SliverPadding`.
  - Inside the list:
    - **Token generation tile**:
      - A button to "Gerar Token de Acesso".
      - Loading state using `AsyncValue` or local `setState(_isLoading)`.
      - If token is generated, show it in a text field with a copy button.
      - Warning message: "Este token só é exibido uma vez. Copie-o antes de sair da página."
    - **Claude Desktop config guide**:
      - Copyable pre-formatted JSON snippet:
        ```json
        {
          "mcpServers": {
            "supanotes": {
              "type": "sse",
              "url": "URL_DO_SERVER/api/v1/mcp/sse",
              "headers": {
                "Authorization": "Bearer <seu_token>"
              }
            }
          }
        }
        ```
    - **Cursor config guide**:
      - Simple text list with copy button for URL: `URL_DO_SERVER/api/v1/mcp`.
- [ ] **Step 3: Add navigation tile to SettingsScreen**
  - Open `lib/features/settings/presentation/settings_screen.dart`.
  - Under the **Advanced** (`Avançado`) section, add:
    ```dart
    SettingsTile.navigation(
      icon: Icons.integration_instructions_outlined,
      title: 'Model Context Protocol (MCP)',
      subtitle: 'Conecte assistentes de IA externos.',
      onTap: () => context.push(AppRoutes.mcp),
    )
    ```
- [ ] **Step 4: Verify UI compiles and runs**
  - Run: `flutter analyze`
  - Expected: Clean analyze report.
- [ ] **Step 5: Commit**
  - Run: `git commit -am "feat(settings): implement McpScreen UI and register settings tile"`

---

## Verification Plan

### Automated Tests
- `go test -v ./internal/mcp`
- `flutter test` (if settings screen tests exist)

### Manual Verification
1. Boot up backend (`make run`).
2. Log in through the client app.
3. Open Settings -> Advanced -> Model Context Protocol (MCP).
4. Click "Gerar Token de Acesso" and confirm token displays.
5. Copy token and verify config snippet placeholders update or copy successfully.
6. Verify configuring MCP client (e.g. inspector or Claude) succeeds with the generated token.
