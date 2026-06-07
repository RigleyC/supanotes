# Implementation Plan — Frontend Critical Bugs + FE-2/3/4/5/6 Completion

> Escopo aprovado: **Opção 2** — só os 5 bugs críticos + completar o que já foi começado (FE-2, FE-3, FE-4, FE-5, FE-6). Sem iniciar FE-7~12.

---

## Estratégia de waves

| Wave | Modo | Agentes | Razão |
|---|---|---|---|
| **1** | Sequencial | 1 agent (fundação) | Tudo depende de schema estável, router wirado e contrato user_id |
| **2** | Paralelo | 3 agents (B/C/D em features disjuntas) | Cada um possui arquivos próprios — zero overlap |

Wave 1 **deve completar** antes de Wave 2 disparar.

---

## Wave 1 — Foundation Agent (sequencial)

**Subagent**: `general`
**Branch**: trabalha em `main` (worktree atual)
**Escopo**: bugs 1–5 + FE-2 DAOs faltantes + FE-3 lifecycle

### Entregáveis

1. **Bug #1 — Router não wirado no main.dart**
   - `lib/main.dart`: trocar `MaterialApp` por `MaterialApp.router` consumindo `goRouterProvider`
   - Remover import `NotesListScreen` (router já cuida)

2. **Bug #2 — user_id hardcoded como `'local'`**
   - Criar `lib/core/auth/current_user.dart` → provider `currentUserIdProvider` lendo de `authControllerProvider`
   - Refatorar `NotesLocalRepository`, `TasksLocalRepository`, `InboxScreen`, `NoteEditorScreen` para receber `userId` em vez de "local"
   - Sync pull agora pode confiar que `json['user_id']` casa com o que está no banco

3. **Bug #3 — Recorrência no `completeTask` é só TODO**
   - Implementar lógica em `tasks_dao.completeTask`:
     - `daily` → nova entry com `due_date = today + 1d`
     - `weekdays` → próximo dia útil (skip sáb/dom)
     - `weekly` → +7d
     - `monthly` → +1 mês
   - Histórico: criar tabela `task_completions` (id, taskId, completedAt) + DAO method `recordCompletion`

4. **Bug #4 — `tags_dao` não existe**
   - Criar `lib/core/database/daos/tags_dao.dart` com `watchTags`, `watchTagsForNote`, CRUD, dirty methods
   - Criar tabela `LocalNoteTags` (junção noteId+tagId) em `lib/core/database/tables/note_tags.dart`
   - Registrar em `@DriftDatabase(tables: [..., LocalNoteTags], daos: [..., TagsDao])`

5. **Bug #5 — Markdown conversion limitada**
   - Extrair conversor para `lib/features/notes/data/markdown_serializer.dart`
   - Suportar: headings (#, ##, ###), bold (**), italic (*), bullet list (-), numbered list (1.), blockquote (>), checklist (TaskNode), paragraphs
   - Wave-2 Agent C usará isto no editor

6. **FE-2 — Métodos DAO faltantes**
   - `NotesDao`: `watchInboxNote(userId)`, `watchNotesByContext(userId, contextId)`, `watchFavorites(userId)`, `softDeleteNote(id)`, `getDirtyNotes()`, `clearDirtyFlag(id)`, `upsertFromRemote(NoteData)`
   - `TasksDao`: `watchOpenTasks(userId)`, `softDeleteTask(id)`, `reopenTask(id)`, `getDirtyTasks()`, `clearDirtyFlag(id)`, `upsertFromRemote(TaskData)`
   - `ContextsDao`: garantir `watchContexts(userId)`, CRUD, dirty methods
   - `TagsDao`: ver bug #4
   - Schema bump → version 2, com `MigrationStrategy` que adiciona `LocalNoteTags` + `task_completions`

7. **FE-3 — Sync lifecycle**
   - Criar `lib/core/sync/sync_state.dart` com `enum SyncStatus { idle, syncing, error, offline }` + `lastSyncedAt` provider via `SharedPreferences`
   - `sync_service.dart`:
     - Expor `Stream<SyncStatus>`
     - Usar `getDirtyNotes/Tasks/...` e `upsertFromRemote` (em vez de `insertOrReplace` cru)
     - Incluir `excerpt`, `updated_at` no payload de push
     - Tags com `isDirty` + `updatedAt` consistentes
   - Integrar lifecycle: em `lib/main.dart` (ou via Riverpod listener) → quando `authControllerProvider` vira `AuthAuthenticated`, dispara `syncServiceProvider`; quando vira `AuthUnauthenticated`, chama `dispose()`
   - Refatorar `OfflineIndicator` para consumir `syncStateProvider` (mostra "syncing…" quando `SyncStatus.syncing`, "offline" quando `SyncStatus.offline`, nada quando idle)

8. **Verificação**
   - `dart run build_runner build --delete-conflicting-outputs`
   - `flutter analyze` — zero erros
   - `flutter test` — todos passam (criar testes mínimos se não existirem)

---

## Wave 2 — Feature Completion Agents (paralelo, 3 agents)

Disparados **após** Wave 1 terminar. Cada agent possui arquivos disjuntos.

### Agent B — FE-4 Home Shell + Notas

**Subagent**: `general`
**Arquivos que possui** (não toca em mais nada):
- `lib/features/notes/domain/note_model.dart` (novo)
- `lib/features/notes/data/notes_repository.dart` (novo, abstrai DAO + sync)
- `lib/features/notes/data/local/notes_local_repository.dart` (modifica — usa NoteModel)
- `lib/features/notes/presentation/notes_list_screen.dart` (modifica — usa NoteCard)
- `lib/features/notes/presentation/widgets/note_card.dart` (novo)
- `lib/features/notes/presentation/widgets/quick_capture_fab.dart` (novo)
- `lib/features/notes/presentation/widgets/main_shell.dart` (novo — Scaffold com BottomNavigationBar)
- `lib/shared/widgets/empty_state.dart` (novo)
- `lib/core/router/app_router.dart` (modifica — adiciona ShellRoute com 4 tabs: /home, /today, /chat, /search; chat e search são placeholders "em breve")

**Funcionalidades**:
- NoteModel (id, title, excerpt, isInbox, favorite, archived, contextId, createdAt, updatedAt) + factory de/para NoteData
- NotesRepository: `watchNotes({contextId?, favoritesOnly?})`, `watchInbox()`, `createNote`, `updateNote`, `toggleFavorite`, `softDelete`
- NoteCard: título bold + excerpt 2 linhas + favorite star + context chip + timeago + swipe-to-delete (com `confirm_dialog` se existir, senão `AlertDialog`) + long-press menu (favorite, delete)
- QuickCaptureFAB: tap → bottom sheet com TextField multi-linha → salva no inbox via `getOrCreateInboxNote` + append → snackbar "Salvo no rascunho"
- MainShell: BottomNavigationBar com 4 tabs (Notas / Hoje / Chat / Busca), tabs Chat e Busca exibem placeholder `EmptyState(icon, "Em breve")`
- Pull-to-refresh na lista: dispara `syncServiceProvider.sync()`
- Empty state: "Crie sua primeira nota" com ícone

**Constraints**:
- ❌ NÃO modificar: `note_editor_screen.dart`, `inbox_screen.dart`, `today_tasks_screen.dart`, qualquer coisa em `tasks/`, `core/database/*`, `core/sync/*`, `auth/*`
- ✅ Pode importar (sem modificar): TodayTasksScreen do FE-6, repos da Wave 1
- Usa `currentUserIdProvider` da Wave 1 para passar userId aos repos

---

### Agent C — FE-5 Editor Polish

**Subagent**: `general`
**Arquivos que possui**:
- `lib/features/notes/presentation/note_editor_screen.dart` (rewrite)
- `lib/features/notes/presentation/inbox_screen.dart` (rewrite)
- `lib/features/notes/presentation/widgets/note_toolbar.dart` (novo)
- `lib/features/notes/presentation/widgets/inbox_organize_sheet.dart` (novo)
- `lib/features/notes/presentation/widgets/save_indicator.dart` (novo)
- `lib/features/agent/data/agent_repository.dart` (novo — somente método `planInboxOrganization` e `applyOrganizationPlan`)
- `lib/features/agent/domain/organization_plan.dart` (novo — model do plano)

**Funcionalidades**:
- Importa `MarkdownSerializer` da Wave 1 (substitui parse/serialize artesanal atual)
- Note editor: título editável fora do super_editor (TextField no topo dentro de SliverAppBar/AppBar) + favorite button no AppBar + SaveIndicator ("Salvando…" / "Salvo" sutil) + toolbar acima do editor
- NoteToolbar: chips/icons para B, I, H1, H2, H3, bullet, numbered, checklist, blockquote — usa `Editor.execute(...)` do super_editor para aplicar
- Inbox editor: AppBar com botão "Organizar" só visível se conteúdo não vazio; tap → bottom sheet
- InboxOrganizeSheet:
  - Estado loading enquanto chama `POST /api/v1/notes/inbox/organize/plan`
  - Exibe lista de itens do plano (trecho original + destino proposto + toggle aceitar/rejeitar)
  - Botão "Aplicar selecionados" → `POST /api/v1/notes/inbox/organize/apply` com IDs dos itens aceitos
  - Snackbar de sucesso + fecha sheet

**Constraints**:
- ❌ NÃO modificar: `notes_list_screen.dart`, `tasks/*`, `core/*`, `auth/*`, qualquer arquivo de Agent B/D
- ❌ NÃO criar `agent/presentation/*` — feature do agent chat (FE-7) não está no escopo
- ✅ Pode usar `apiClientProvider` para chamar backend
- Usa `currentUserIdProvider` da Wave 1

---

### Agent D — FE-6 Tasks Completas

**Subagent**: `general`
**Arquivos que possui**:
- `lib/features/tasks/domain/task_model.dart` (novo)
- `lib/features/tasks/data/tasks_repository.dart` (novo — abstrai DAO)
- `lib/features/tasks/data/local/tasks_local_repository.dart` (modifica — usa TaskModel)
- `lib/features/tasks/presentation/today_tasks_screen.dart` (rewrite — seções)
- `lib/features/tasks/presentation/widgets/task_tile.dart` (novo)
- `lib/features/tasks/presentation/widgets/task_checkbox.dart` (novo)
- `lib/features/tasks/presentation/widgets/due_date_picker.dart` (novo)
- `lib/features/tasks/presentation/widgets/recurrence_picker.dart` (novo)
- `lib/features/tasks/presentation/widgets/note_tasks_list.dart` (novo)
- `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` (novo)
- `lib/features/tasks/presentation/widgets/quick_task_fab.dart` (novo)

**Funcionalidades**:
- TaskModel: id, noteId, title, status, position, dueDate, completedAt, recurrence, createdAt, updatedAt + computed `isOverdue`, `isDueToday`, `isRepeating`
- TasksRepository: `watchTodayTasks()`, `watchOverdueTasks()`, `watchUndatedOpenTasks()`, `watchByNote(noteId)`, `createTask`, `completeTask`, `reopenTask`, `updateTask`, `deleteTask`, `reorderTask`
- TaskTile: checkbox + título + due-date badge (verde/vermelho/cinza) + recurrence icon + swipe-right (complete) + swipe-left (delete) + tap (edit sheet)
- TaskCheckbox: animação scale + cor + strikethrough fade
- DueDatePicker: chips "Hoje", "Amanhã", "Próx segunda", "Escolher data" → showDatePicker
- RecurrencePicker: chips "Nenhuma", "Diária", "Dias úteis", "Semanal", "Mensal" — retorna string
- NoteTasksList: widget embeddable que recebe noteId → lista de TaskTile + ReorderableListView + botão "+" inline
- TaskEditSheet: bottom sheet com título, due date, recurrence
- QuickTaskFAB: FAB no today screen → bottom sheet (título + due opcional) → cria task no inbox
- TodayTasksScreen: três seções colapsáveis — "Atrasadas" (vermelho), "Hoje", "Sem data"; empty state "Nenhuma task para hoje 🎉"

**Constraints**:
- ❌ NÃO modificar: notes/*, core/*, auth/*, qualquer arquivo de Agent B/C
- ✅ Recorrência usa `recurrence` do banco mas a LÓGICA já foi implementada na Wave 1 — agent D só consome
- Usa `currentUserIdProvider` da Wave 1

---

## Pós-execução (eu integro)

1. Cada agente devolve resumo de arquivos tocados
2. Eu rodo `flutter analyze` + `flutter test`
3. Se algo quebrar, dispatcho agente de fix focado no erro
4. Atualizo `walkthrough.md` com seção "FE-1~6 Completion"
5. Reporto status final ao usuário

---

## Riscos identificados

| Risco | Mitigação |
|---|---|
| Agent C precisa de `MarkdownSerializer` da Wave 1 | Wave 1 cria e exporta; Wave 2 só importa |
| Schema bump v1→v2 pode quebrar DB local existente | `MigrationStrategy` com `onUpgrade` adicionando tabelas novas; dados antigos preservados |
| `currentUserIdProvider` retorna null se ainda em loading | Repos devolvem stream vazio nesse estado; UI já trata `AsyncValue.loading` |
| Backend não tem endpoint `inbox/organize/plan`? | Verificado `internal/agent` existe; se o endpoint específico faltar, Agent C devolve stub + relatório |
| `build_runner` em paralelo causa race | Só Wave 1 roda build_runner; Wave 2 só consome código gerado |
