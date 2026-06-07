# Refatoracao Termo-Nuclear — SupaNotes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminar god methods/classes, corrigir violações SOLID, centralizar validadores/widgets globais, desacoplar views de repositories, e estabelecer transações atômicas no backend.

**Architecture:** Backend Go ganha camada `internal/web/` (helpers compartilhados) + `internal/dto/` (desacoplamento DB/API) + transações `pgx.Tx` para operações multi-tabela. Frontend Flutter ganha 1 controller por tela em `controllers/` + widgets globais em `shared/widgets/` + `StatefulShellRoute` no GoRouter.

**Tech Stack:** Go 1.22+ (Echo, pgx, sqlc), Flutter 3.22+ (Riverpod, GoRouter, Drift, super_editor)

---

## Phase 0 — Foundation (Backend Helpers + Frontend Globals)

### Task 0.1: Criar `internal/web/` — Helpers HTTP Compartilhados

**Files:**
- Create: `backend/internal/web/context.go`
- Create: `backend/internal/web/response.go`
- Create: `backend/internal/web/bind.go`
- Modify: `backend/cmd/server/main.go` (registrar validator global no Echo)

**Descrição:**
Crie o pacote `internal/web` com helpers que eliminam a repetição massiva nos handlers.

- `context.go`:
  ```go
  func UserID(c echo.Context) (pgtype.UUID, error)
  ```
  - Parseia `c.Get("user_id").(string)` com `pgtype.UUID.Scan()`.
  - Retorna `echo.NewHTTPError(401, ...)` se ausente ou inválido.

- `response.go`:
  ```go
  func JSONError(c echo.Context, status int, msg string) error
  func JSONValidationError(c echo.Context, err error) error
  func FormatTime(t pgtype.Timestamptz) string
  func UUIDToString(u pgtype.UUID) string
  func OptUUID(s *string) (*pgtype.UUID, error)
  ```

- `bind.go`:
  ```go
  func BindAndValidate(c echo.Context, req any) error
  ```
  - Unifica `c.Bind(req)` + `c.Validate(req)` em um único helper.
  - Retorna `*echo.HTTPError` pronto para ser retornado pelo handler.

- `main.go`: Configure `e.Validator = &CustomValidator{validator: validator.New()}` UMA vez. Remova `validator.New` de todos os handlers.

**Critérios de Aceitação:**
- `go build ./...` passa.
- Nenhum handler deve mais chamar `validator.New` (verificar com grep).

---

### Task 0.2: Criar `internal/dto/` — Data Transfer Objects

**Files:**
- Create: `backend/internal/dto/note.go`
- Create: `backend/internal/dto/task.go`
- Create: `backend/internal/dto/context.go`
- Create: `backend/internal/dto/tag.go`
- Create: `backend/internal/dto/memory.go`
- Create: `backend/internal/dto/message.go`
- Create: `backend/internal/dto/search.go`
- Create: `backend/internal/dto/sync.go`

**Descrição:**
Crie structs de response que NUNCA expõem `sqlcgen.*` ou `pgtype.UUID`/`pgtype.Timestamptz` diretamente. Todos os IDs devem ser `string`. Todas as datas devem ser `string` (RFC3339).

Exemplo (`note.go`):
```go
type NoteResponse struct {
    ID          string    `json:"id"`
    Title       string    `json:"title"`
    Content     string    `json:"content"`
    IsInbox     bool      `json:"is_inbox"`
    IsFavorite  bool      `json:"is_favorite"`
    ContextID   *string   `json:"context_id,omitempty"`
    CreatedAt   string    `json:"created_at"`
    UpdatedAt   string    `json:"updated_at"`
}
```

**Critérios de Aceitação:**
- `go build ./...` passa.
- Nenhum handler usa `sqlcgen.Note` como tipo de response.

---

### Task 0.3: Criar `internal/mapper/` — Mapeamento Generico

**Files:**
- Create: `backend/internal/mapper/mapper.go`

**Descrição:**
Funções puras para converter tipos do banco em strings.

```go
func UUID(u pgtype.UUID) string
func OptUUID(u pgtype.UUID) *string
func Time(t pgtype.Timestamptz) string
func OptTime(t pgtype.Timestamptz) *string
```

**Critérios de Aceitação:**
- Cobertura 100% com testes unitários simples.

---

### Task 0.4: Criar Widgets Globais Flutter

**Files:**
- Create: `lib/shared/widgets/app_button.dart`
- Create: `lib/shared/widgets/app_input.dart`
- Create: `lib/shared/widgets/app_bottom_sheet.dart`
- Create: `lib/shared/widgets/app_snackbar.dart`
- Create: `lib/shared/widgets/app_choice_chip.dart`
- Create: `lib/shared/widgets/app_error_view.dart`
- Create: `lib/shared/widgets/app_card.dart`
- Create: `lib/shared/widgets/app_status_chip.dart`

**Descrição:**
Proíba qualquer tela de chamar `showModalBottomSheet`, `ScaffoldMessenger.of(context).showSnackBar`, `AlertDialog`, ou `ElevatedButton` diretamente.

- `AppButton`: recebe `VoidCallback? onPressed`, `String text`, `bool isLoading`, `AppButtonVariant variant`.
- `AppInput`: `TextFormField` padronizado.
- `AppBottomSheet`: função global `Future<T?> showAppBottomSheet<T>(BuildContext context, ...)`.
- `AppMessenger`: classe estática com `showSuccess`, `showError`, `showInfo`.
- `AppChoiceChip`: extrair o `_Chip` de `due_date_picker`/`recurrence_picker`.
- `AppErrorView`: widget com ícone, título, subtítulo, botão retry.
- `AppCard`: Card com `elevation: 0`.
- `AppStatusChip`: Container + padding + borderRadius.

**Critérios de Aceitação:**
- `flutter analyze` passa para todos os novos arquivos.

---

### Task 0.5: Criar Validadores Estaticos Flutter

**Files:**
- Create: `lib/core/validators/input_validators.dart`

**Descrição:**
Extraia TODOS os validadores inline das telas para métodos estáticos puros.

```dart
class EmailValidator { static String? validate(String? value); }
class PasswordValidator { static String? validate(String? value, {int minLength = 8}); }
class NameValidator { static String? validate(String? value); }
class NonEmptyValidator { static String? validate(String? value, {required String fieldName}); }
```

**Critérios de Aceitação:**
- `login_screen.dart` e `register_screen.dart` usam `EmailValidator.validate`.

---

### Task 0.6: Corrigir `AppTheme` e `AppSpacing`

**Files:**
- Modify: `lib/shared/theme/app_spacing.dart`
- Modify: `lib/shared/theme/app_theme.dart`
- Modify: `lib/shared/theme/app_colors.dart`
- Create: `lib/shared/theme/app_semantic_colors.dart` (ThemeExtension)

**Descrição:**
- `app_spacing.dart`: adicionar `buttonHeight = 48.0`, `iconSm/Md/Lg`, `elevationSm/Md`, `radiusFull = 999.0`.
- `app_theme.dart`: extrair helper `_buildInputBorder()`.
- `app_colors.dart`: criar `AppSemanticColors` via `ThemeExtension`.
- `offline_indicator.dart`: usar `ColorScheme` + `AppTypography` + `AppSpacing`.

**Critérios de Aceitação:**
- `offline_indicator.dart` não contém `Colors.` (verificar com grep).

---

### Task 0.7: Corrigir `ApiClient` e `AuthInterceptor`

**Files:**
- Modify: `lib/core/api/api_client.dart`
- Modify: `lib/core/api/auth_interceptor.dart`

**Descrição:**
- `api_client.dart`: tornar `dio` privado (`_dio`). Expor métodos proxy (`get`, `post`, etc).
- `auth_interceptor.dart`: criar factory `Dio _createBaseDio()` compartilhada. Corrigir `_isAuthRoute` para `path.startsWith('/api/v1/auth/')`.

**Critérios de Aceitação:**
- Nenhum arquivo fora de `api_client.dart` acessa `.dio`.

---

## Phase 1 — Backend Core

### Task 1.1: Extrair OnboardingService (auth.Register)

**Files:**
- Modify: `backend/internal/auth/service.go`
- Create: `backend/internal/onboarding/service.go`
- Modify: `backend/internal/auth/handler.go`
- Modify: `backend/cmd/server/main.go`

**Descrição:**
Quebrar `auth.Service.Register`: auth cria só o usuário; `onboarding.Service.OnboardUser` cria settings, inbox, soul, routines dentro de transação.

---

### Task 1.2: Transacao em sync.Push

**Files:**
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/repository.go`
- Modify: `backend/internal/sync/handler.go`

**Descrição:**
Envolver Push em `pgx.Tx`. Corrigir `GetSyncTags` que ignora `lastSyncedAt`. Nao expor `err.Error()` cru.

---

### Task 1.3: Refatorar Handlers Gordos

**Files:**
- Create+Modify: `settings`, `contexts`, `soul`, `tags`, `notifications` (service + repository + handler)

**Descrição:**
Extrair service/repository. Handlers finos (<80 linhas). Validar requests ausentes.

---

### Task 1.4: Unificar UUID Parse e Responses

**Files:**
- Modify: TODOS os handlers internos

**Descrição:**
Substituir parse manual por `web.UserID(c)`. Substituir `map[string]string` por `web.JSONError`. Validar params ignorados (ex: `note_id` in tasks).

---

### Task 1.5: Otimizar CompleteTask

**Files:**
- Modify: `backend/internal/tasks/service.go`
- Modify: `backend/internal/tasks/repository.go`

**Descrição:**
Reduzir 4 queries para 1-2. Eliminar `GetTaskByID` desnecessário em Update/Delete.

---

### Task 1.6: Eliminar DRY em search

**Files:**
- Modify: `backend/internal/search/service.go`

**Descrição:**
Extrair `mapRowToSearchResult` unico. Extrair `mockEmbedding()` para isolado.

---

### Task 1.7: Corrigir agent tools e context

**Files:**
- Modify: `backend/internal/agent/tools.go`
- Modify: `backend/internal/agent/context.go`
- Modify: `backend/internal/agent/loop.go`

**Descrição:**
Substituir fake embedding por erro explícito. Padronizar UUID formatting. Extrair helpers `parseArgs[T]`. Usar `strings.Builder`.

---

### Task 1.8: Usar robfig/cron corretamente

**Files:**
- Modify: `backend/internal/routines/runner.go`

**Descrição:**
Substituir polling manual por `AddFunc`. Adicionar semaphore. Mover cleanup para separado.

---

### Task 1.9: Separar Gateway

**Files:**
- Modify: `backend/internal/gateway/repository.go`
- Create: `backend/internal/gateway/telegram_client.go`
- Modify: `backend/internal/gateway/handler.go`

**Descrição:**
Separar SQL raw de HTTP client. Quebrar Webhook em sub-metodos.

---

## Phase 2 — Frontend Core

### Task 2.1: Criar Controllers (1 por tela)

**Files:**
- Create: 12 controllers em `lib/features/*/presentation/controllers/`
- Modify: todas as telas para usar controllers

**Descrição:**
Cada controller é um `AsyncNotifier`. View nunca acessa repository diretamente.

---

### Task 2.2: StatefulShellRoute no GoRouter

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/notes/presentation/widgets/main_shell.dart`

**Descrição:**
Substituir rota `/home` por `StatefulShellRoute` com 4 branches. Tabs endereçáveis.

---

### Task 2.3: Extrair SyncRepository e SyncMapper

**Files:**
- Modify: `lib/core/sync/sync_service.dart`
- Create: `lib/core/sync/sync_repository.dart`
- Create: `lib/core/sync/sync_mapper.dart`

**Descrição:**
Quebrar God Object de 306 linhas. Isolar HTTP, JSON parsing, SharedPreferences.

---

### Task 2.4: Refatorar notes_list_screen + today_tasks_screen

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Modify: `lib/features/tasks/presentation/today_tasks_screen.dart`

**Descrição:**
Criar controllers. Remover acesso direto a repositories. Usar widgets globais.

---

### Task 2.5: Refatorar note_editor_screen + inbox_screen

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`

**Descrição:**
Extrair NoteEditorController. Remover codigo comentado morto. Corrigir bug de layout.

---

### Task 2.6: Refatorar telegram_link_screen + contexts_screen

**Files:**
- Modify: `lib/features/telegram/presentation/telegram_link_screen.dart`
- Modify: `lib/features/settings/presentation/contexts_screen.dart`

**Descrição:**
Extrair TelegramLinkController e ContextsController. Quebrar em widgets menores.

---

### Task 2.7: Refatorar telas restantes

**Files:**
- Modify: `soul_editor_screen`, `settings_screen`, `routines_screen`, `brief_history_screen`, `search_screen`

**Descrição:**
Criar controllers para cada. Remover `setState`/`addPostFrameCallback`.

---

### Task 2.8: Extrair ChatController

**Files:**
- Modify: `lib/features/agent/presentation/chat_screen.dart`
- Create: `lib/features/agent/presentation/controllers/chat_controller.dart`

**Descrição:**
Extrair controller do arquivo da screen.

---

## Phase 3 — Polimento

### Task 3.1: Extrair duplicacoes (DueDatePicker + RecurrencePicker)

**Files:**
- Modify: `due_date_picker.dart`, `recurrence_picker.dart`, `task_edit_sheet.dart`
- Create: `app_dismissible_wrapper.dart`, `app_choice_chip.dart`

### Task 3.2: Corrigir Agent + Search widgets

**Files:**
- Modify: `message_bubble.dart`, `search_result_tile.dart`, `search_bar.dart`

### Task 3.3: Interfaces de repositories

**Files:**
- Create: interfaces para NotesRepository, TasksRepository, SettingsRepository

---

## Phase 4 — Verificacao Final

### Task 4.1: Backend verification
`go build ./...`, `go test ./...`, `go vet ./...`

### Task 4.2: Frontend verification
`flutter analyze`, `flutter test`, `dart run build_runner build`

### Task 4.3: Documentacao
Update `walkthrough.md`, `ROADMAP_FRONTEND.md`

---

## Dependencies

```
Phase 0 (Foundation) -> Phase 1 (Backend Core) -> Phase 2 (Frontend Core) -> Phase 3 (Polimento) -> Phase 4 (Verificacao)
```

Phase 0 and Phase 1 can be done in parallel. Phase 2 depends on Phase 0 for widgets/validators.

---

## Riscos e Mitigacoes

| Risco | Impacto | Mitigacao |
|-------|---------|-----------|
| Quebrar API para o Flutter | Alto | DTOs primeiro, garantir JSON identico |
| build_runner race condition | Medio | So rodar na Phase 0 e 4 |
| Telas grandes dificeis de testar | Alto | Refatorar 1 tela por vez |
| Embedding real nao pronto | Alto | Retornar erro explicito, nao vetor fake |

---

## Estimativa

| Fase | Tarefas | Estimativa |
|------|---------|------------|
| Phase 0 | 7 | 2-3 dias |
| Phase 1 | 9 | 3-4 dias |
| Phase 2 | 8 | 4-5 dias |
| Phase 3 | 3 | 1-2 dias |
| Phase 4 | 3 | 1 dia |
| **Total** | **30** | **11-15 dias** |
