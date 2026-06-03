# SupaNotes — Agent Conventions

This file defines the conventions, architecture decisions, and rules all agents and contributors must follow when implementing features or fixes in this project.

---

## Project Overview

**SupaNotes** is a personal notes app with proactive AI capabilities.  
- **Frontend**: Flutter (mobile + desktop)  
- **Backend**: Go (REST API, AI proxy, business logic)

---

## Architecture

```
supanotes/
├── lib/               # Flutter frontend (Dart)
├── backend/           # Go backend
│   ├── cmd/server/    # Entrypoint
│   ├── internal/      # Business logic, handlers
│   └── Dockerfile
└── agents.md          # This file
```

---

## Conventions

### Before ANY implementation
1. Read this file fully.
2. Understand all related files before proposing changes.
3. Check existing patterns before creating new ones.

### Flutter (Frontend)
- Use `super_editor` for rich text editing.
- Keep business logic out of widgets — use services/repositories.
- No hardcoded strings; use constants.
- File naming: `snake_case.dart`.

### Go (Backend)
- Module name: `github.com/RigleyC/supanotes`
- Package layout follows [Standard Go Project Layout](https://github.com/golang-standards/project-layout).
- Use `internal/` for private packages.
- Handlers are thin — delegate to services.
- Configuration via environment variables (see `backend/.env.example`).
- All endpoints must have a health check equivalent.
- Use structured logging (e.g., `log/slog`).

### Git
- Branch naming: `feat/<name>`, `fix/<name>`, `chore/<name>`
- Commit format: `type(scope): description` (Conventional Commits)
- Never commit `.env` files — only `.env.example`.

### API Design
- All API routes prefixed with `/api/v1/`
- JSON request/response bodies.
- Consistent error format:
  ```json
  { "error": "message here" }
  ```

---

## Environment Variables

See `backend/.env.example` for all required variables.

---

## How to Propose a Feature

1. Read `agents.md` and related source files.
2. Create or update `implementation_plan.md` artifact.
3. Wait for user approval.
4. Implement and update `task.md` as you go.
5. Create `walkthrough.md` after completion.
