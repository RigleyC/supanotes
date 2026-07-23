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

### Flutter UI Screen Conventions

Cada tela deve seguir o padrão abaixo. **Toda tela nova deve seguir estas regras; telas existentes devem ser refatoradas gradualmente.**

#### Estrutura básica da tela

```
Scaffold(
  body: CustomScrollView(
    slivers: [
      SliverAppBar.medium(title: const Text('Title')),
      SliverPadding(
        sliver: SliverList(
          delegate: SliverChildListDelegate([ ...conteúdo ]),
        ),
      ),
    ],
  ),
)
```

- Use `CustomScrollView` + `SliverAppBar.medium` + `SliverList` como estrutura padrão.
- Use `SliverPadding` para padding ao redor do `SliverList`.
- Use `SliverFillRemaining` para telas que precisam ocupar todo o espaço (loading, estados especiais).
- Use `bottomNavigationBar` (quando houver botões de ação fixos no rodapé) em vez de widgets soltos no body.

#### Estado e requisições

- Use `AsyncValue.when(data:loading:error:)` em vez de checar `.isLoading` / `.hasError` manualmente. **PROIBIDO**:
  ```dart
  // PROIBIDO
  if (asyncValue.isLoading) return ...;
  if (asyncValue.hasError) return ...;
  final data = asyncValue.asData?.value;
  if (data == null) return ...;

  // OBRIGATÓRIO
  return asyncValue.when(
    data: (data) => ...,
    loading: () => ...,
    error: (err, _) => ...,
  );
  ```
- **PROIBIDO**: booleanos como `_isLoading`, `_isSaving`, `_isEditing`, `_initialized`, `_waitingForLink` para estado de requisição. Use o estado do provider + `AsyncValue`.
- Exceção: estado de UI local (query string, visibilidade de sheet, countdown) pode usar `setState` ou `ValueNotifier` conforme as regras de Riverpod acima.
- **PROIBIDO**: modo visualização/edição. Telas devem usar apenas modo edição.

#### Botões e componentes

- Use **sempre** os componentes compartilhados do app: `AppButton`, `AppInput`, `AppCard`, `AppErrorView`, `AppBottomSheet`, `confirm_dialog.dart`, etc.
- **PROIBIDO**: `FloatingActionButton`, `ElevatedButton`, `TextButton`, `OutlinedButton`, `FilledButton` — use `AppButton` com a variante apropriada.
- Se um componente necessário não existir, crie no `shared/widgets/`.
- Use `FloatingActionButton` ou `QuickActionFabs` apenas para ações principais que justifiquem FAB.

#### Métodos privados e widgets separados

- **PROIBIDO** criar métodos privados como `_buildBody`, `_buildHeader`, `_modeBanner`, `_editor`, `_preview`, `_footerActions` para trechos que podem ficar inline no `build()`.
- Para lógica complexa que justifique extração, prefira criar widgets privados reutilizáveis (classes `_FooWidget extends StatelessWidget`).
- Ações de callback (onPressed handlers) que precisam de contexto podem usar métodos nomeados privados (`_onSave`, `_onDelete`).

#### Strings

- Strings simples (títulos, labels de botão, placeholders) **inline**: `const Text('Configurações')` — sem classe de strings para isso.
- Strings complexas (mensagens longas, textos com interpolação, usados em múltiplos lugares) vão em um arquivo de constantes do feature (`domain/<feature>_strings.dart`).
- **PROIBIDO** criar classes `_FooStrings` dentro do arquivo de screen.

#### Dialogs e Modals

- Dialogs de confirmação: use `showConfirmDialog(...)` de `confirm_dialog.dart` — **PROIBIDO** `showDialog` + `AlertDialog` inline.
- Modals/bottom sheets: crie um widget dedicado (ex. `NewContextSheet`) e use `showAppBottomSheet(context, builder: (_) => SheetWidget())`.
- Dialogs personalizados: crie um widget simples (ex. `class SomeDialog extends StatelessWidget`) que receba callbacks e use com o método global.

### Go (Backend)
- Module name: `github.com/RigleyC/supanotes`
- Package layout follows [Standard Go Project Layout](https://github.com/golang-standards/project-layout).
- Use `internal/` for private packages.
- Handlers are thin — delegate to services.
- Configuration via environment variables (see `backend/.env.example`).
- All endpoints must have a health check equivalent.
- Use structured logging (e.g., `log/slog`).

### State Management (Riverpod 3.x)

- **OBRIGATÓRIO**: providers declarados **manualmente** com `Notifier`/`StreamProvider`/`FutureProvider`/`AsyncNotifier`.
  **PROIBIDO**: codegen (`@riverpod`, `riverpod_generator`, `.g.dart`).
- **PROIBIDO**: `StateNotifier` (deprecated), classes `State`/`Store` com `copyWith` manual,
  `state.value!` sem checagem, `repo.watchX().first` em `build()`.
- Use `StreamProvider` / `StreamProvider.family` para dados do Drift (nunca `.first` em `build()`).
- Use `FutureProvider` / `FutureProvider.family` para fetch HTTP único.
- Use `Notifier`/`AsyncNotifier` **somente** para state genuinamente compartilhado + mutação complexa
  (auth, chat, sync).
- State de UI local (save status, countdown, query string, visibilidade de sheet)
  fica no widget com `setState` ou `ValueNotifier` — não vira provider.
- **`.autoDispose` por padrão**. Exceções: `authController`, `goRouter`,
  `appDatabase`, `apiClient`, `authLocalStorage`, `authRepository`,
  `syncService`, `syncState`, `connectivityMonitor`, `sessionCache`.
- Erros não podem ser engolidos. `catch (e) { return const EmptyState() }` é proibido —
  propague na UI via `AsyncValue.error`.
- `AsyncValue` já cobre `loading`/`data`/`error`. Não crie campos `isLoading`/`error`
  dentro do state — eles duplicam o que o Riverpod já te dá.
- Estado digitado pelo usuário usa `TextEditingController`, não provider.
- Regras detalhadas e exemplos em `RIVERPOD.md` (raiz do projeto).

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

## System Invariants & Avoidance Rules

### REST/OT Document Snapshot as Single Source of Truth

The REST/OT canonical document snapshot (`notes.document` JSONB) is the single source of truth for note content and task metadata (dueDate, dueTime, recurrence, checked state).

- **Task Projections**: `TaskProjectionEngine` projects task blocks from the canonical REST/OT document snapshot into the local Drift SQLite `tasks` table.
- **UI Editing**: The Flutter UI writes block operations strictly through `NoteSyncSession` / `EditorOperationCapture` / `NoteOperationAdapter`.
- **Relational Isolation**: Direct, non-projection writes to SQLite `tasks` table are strictly prohibited for task content and metadata changes. All task updates flow through document block operations first.

