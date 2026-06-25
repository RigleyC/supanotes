# Design Spec: Complete MCP Server & Frontend Token Settings

This document defines the design and requirements for completing the Model Context Protocol (MCP) server endpoints and adding the frontend user interface for token generation.

## Purpose

Enables users to connect external AI agents (like Claude Desktop and Cursor) to their SupaNotes account. It requires:
1. **Frontend Settings Page**: An option in the settings menu allowing users to generate a long-lived JWT token and copy connection configurations (specifically for Claude Desktop and Cursor).
2. **Backend Tool Schemas**: Defining detailed JSON schemas for all MCP tools instead of using empty schemas, allowing LLM clients to understand the tool parameters.
3. **Backend Unit Tests**: Robust unit testing of the MCP tools mapping, parameters, and error responses.

---

## 1. Frontend Design

### Routes & Repository
- **Route**: `AppRoutes.mcp = '/settings/mcp'` mapped to `McpScreen` in GoRouter.
- **Repository Method**:
  ```dart
  Future<String> generateMcpToken();
  ```
  Issues a `POST /auth/mcp-token` request to the backend and returns the raw `mcp_token` string.

### User Interface (`McpScreen`)
- Placed under the **Advanced** section in the settings screen.
- Layout:
  - CustomScrollView + SliverAppBar.medium + SliverList.
  - **Token Card**:
    - A button to "Gerar Token de Acesso".
    - If generated, displays the token inside a read-only text field with a copy button.
    - A short security alert warning that the token is only shown once.
  - **Setup Block (Claude Desktop)**:
    - Pre-formatted JSON snippet representing the `claude_desktop_config.json` block.
    - Interpolates the generated token if available (otherwise shows `<token>`).
    - Copy button for the JSON snippet.
  - **Setup Block (Cursor)**:
    - Lists the connection fields: Type (SSE), URL (`${ApiConstants.baseUrl}/mcp`), and Header (`Authorization: Bearer <token>`).
    - Copy button for the URL.

---

## 2. Backend Design

### Precise JSON Tool Schemas
Replace `emptySchema` with precise JSON schema definitions in `backend/internal/mcp/tools.go`.
Example schemas:
- **`get_note`**:
  ```json
  {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "description": "The UUID of the note to retrieve"
      }
    },
    "required": ["id"]
  }
  ```
- **`create_note`**:
  ```json
  {
    "type": "object",
    "properties": {
      "content": {
        "type": "string",
        "description": "The text content of the note"
      }
    },
    "required": ["content"]
  }
  ```
- Repeat for other mutation and query tools (`update_note`, `delete_note`, `create_task`, etc.) requiring arguments.

### Tool Tests
Implement unit tests in `backend/internal/mcp/tools_test.go` by:
- Creating mock structures for backend services.
- Verifying parameter parsing, business logic invocation, and return format of `CallToolResult` (including error handling) for key tools.
