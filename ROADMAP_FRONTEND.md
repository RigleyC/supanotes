# SupaNotes — Roadmap Frontend (Flutter) v1

Plano feature-by-feature exclusivo do frontend Flutter, derivado do [escopo técnico v3](SuperNotes/notes-agent-scope-v3.md).  
Cada feature é uma unidade independente com entregáveis granulares, arquivos, widgets e telas específicas.

> **Stack**: Flutter + Riverpod + Go Router + Dio + Drift + super_editor  
> **Convenção**: commits `feat(flutter): descrição` — cada feature em branch `feat/flutter-<nome>`  
> **Princípio**: local-first — leitura/escrita sempre do SQLite local (Drift), sync em background

---

## Legenda

- `[CORE]` — Pacote `core/` (infra compartilhada)
- `[FEAT]` — Pacote `features/` (feature específica)
- `[SHARED]` — Pacote `shared/` (widgets e tema reutilizáveis)
- `[CONFIG]` — Arquivos de configuração (pubspec, análise, assets)

---

## Estrutura final de `lib/`

```
lib/
├── main.dart
├── core/
│   ├── api/
│   │   ├── api_client.dart              # Dio instance + interceptors
│   │   ├── auth_interceptor.dart        # JWT auto-refresh
│   │   └── api_exceptions.dart          # Error types padronizados
│   ├── database/
│   │   ├── app_database.dart            # Drift database class
│   │   ├── app_database.g.dart          # Gerado pelo build_runner
│   │   ├── tables/
│   │   │   ├── local_notes.dart
│   │   │   ├── local_tasks.dart
│   │   │   ├── local_contexts.dart
│   │   │   └── local_tags.dart
│   │   └── daos/
│   │       ├── notes_dao.dart
│   │       ├── tasks_dao.dart
│   │       ├── contexts_dao.dart
│   │       └── tags_dao.dart
│   ├── sync/
│   │   ├── sync_service.dart            # Push dirty + pull remote
│   │   ├── sync_state.dart              # SyncStatus enum + lastSyncedAt
│   │   └── connectivity_monitor.dart    # Observa rede
│   ├── di/
│   │   └── providers.dart               # Riverpod providers globais
│   ├── router/
│   │   ├── app_router.dart              # GoRouter config
│   │   └── auth_guard.dart              # Redirect se não autenticado
│   └── constants/
│       ├── api_constants.dart           # Base URL, timeouts
│       └── app_constants.dart           # Durations, limites
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── auth_repository.dart     # Login, register, refresh, logout
│   │   │   └── auth_local_storage.dart  # Persiste tokens (secure storage)
│   │   ├── domain/
│   │   │   └── auth_state.dart          # AuthState (authenticated/unauthenticated)
│   │   └── presentation/
│   │       ├── login_screen.dart
│   │       ├── register_screen.dart
│   │       └── widgets/
│   │           ├── auth_form_field.dart
│   │           └── auth_button.dart
│   ├── notes/
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   └── notes_local_source.dart  # Lê/escreve do Drift
│   │   │   └── remote/
│   │   │       └── notes_remote_source.dart # API calls (sync only)
│   │   ├── domain/
│   │   │   ├── note_model.dart
│   │   │   └── notes_repository.dart        # Abstrai local + remote
│   │   └── presentation/
│   │       ├── notes_list_screen.dart
│   │       ├── note_editor_screen.dart
│   │       ├── inbox_screen.dart
│   │       └── widgets/
│   │           ├── note_card.dart
│   │           ├── note_toolbar.dart
│   │           ├── inbox_organize_sheet.dart
│   │           └── quick_capture_fab.dart
│   ├── tasks/
│   │   ├── data/
│   │   │   ├── local/
│   │   │   │   └── tasks_local_source.dart
│   │   │   └── remote/
│   │   │       └── tasks_remote_source.dart
│   │   ├── domain/
│   │   │   ├── task_model.dart
│   │   │   └── tasks_repository.dart
│   │   └── presentation/
│   │       ├── today_screen.dart
│   │       ├── note_tasks_list.dart
│   │       └── widgets/
│   │           ├── task_checkbox.dart
│   │           ├── task_tile.dart
│   │           ├── due_date_picker.dart
│   │           └── recurrence_picker.dart
│   ├── agent/
│   │   ├── data/
│   │   │   ├── agent_repository.dart
│   │   │   └── sse_client.dart              # SSE parser (~30 linhas)
│   │   ├── domain/
│   │   │   ├── message_model.dart
│   │   │   └── session_manager.dart         # session_id lifecycle
│   │   └── presentation/
│   │       ├── chat_screen.dart
│   │       └── widgets/
│   │           ├── message_bubble.dart
│   │           ├── chat_input.dart
│   │           ├── typing_indicator.dart
│   │           └── new_session_button.dart
│   ├── search/
│   │   ├── data/
│   │   │   └── search_repository.dart
│   │   ├── domain/
│   │   │   └── search_result_model.dart
│   │   └── presentation/
│   │       ├── search_screen.dart
│   │       └── widgets/
│   │           ├── search_bar.dart
│   │           ├── search_result_tile.dart
│   │           └── search_mode_toggle.dart
│   ├── routines/
│   │   ├── data/
│   │   │   └── routines_repository.dart
│   │   ├── domain/
│   │   │   ├── routine_model.dart
│   │   │   └── routine_log_model.dart
│   │   └── presentation/
│   │       ├── routines_screen.dart
│   │       ├── brief_history_screen.dart
│   │       └── widgets/
│   │           ├── brief_schedule_card.dart
│   │           ├── day_selector.dart
│   │           ├── time_picker_field.dart
│   │           └── brief_log_tile.dart
│   └── settings/
│       ├── data/
│       │   └── settings_repository.dart
│       └── presentation/
│           ├── settings_screen.dart
│           ├── soul_editor_screen.dart
│           ├── contexts_screen.dart
│           ├── telegram_link_screen.dart
│           └── widgets/
│               ├── settings_tile.dart
│               └── telegram_status_badge.dart
└── shared/
    ├── widgets/
    │   ├── offline_banner.dart
    │   ├── loading_overlay.dart
    │   ├── empty_state.dart
    │   ├── error_snackbar.dart
    │   ├── confirm_dialog.dart
    │   └── markdown_renderer.dart
    └── theme/
        ├── app_theme.dart                   # ThemeData (light + dark)
        ├── app_colors.dart                  # Paleta de cores
        ├── app_typography.dart              # TextStyles (Google Fonts)
        └── app_spacing.dart                 # Paddings, margins, border radius
```

---

## FE-0 — Tema, Design System e Configuração

**Objetivo**: Limpar o boilerplate do Flutter, instalar todas as dependências, definir o design system completo e a estrutura de pastas.

**Branch**: `feat/flutter-design-system`

### Entregáveis

- [ ] `[CONFIG]` Atualizar `pubspec.yaml` com todas as dependências:
  ```yaml
  # State management
  flutter_riverpod: ^2.x
  riverpod_annotation: ^2.x

  # Routing
  go_router: ^14.x

  # HTTP
  dio: ^5.x

  # Local database
  drift: ^2.x
  sqlite3_flutter_libs: ^0.5.x

  # Auth storage
  flutter_secure_storage: ^9.x

  # Connectivity
  connectivity_plus: ^6.x

  # Editor (já existe)
  super_editor: (git fork)

  # Fonts
  google_fonts: ^6.x

  # Utils
  uuid: ^4.x
  intl: ^0.19.x
  timeago: ^3.x
  ```
  Dev dependencies:
  ```yaml
  riverpod_generator: ^2.x
  build_runner: ^2.x
  drift_dev: ^2.x
  ```
- [ ] `[SHARED]` `shared/theme/app_colors.dart`:
  - Paleta principal (primary, secondary, surface, background, error)
  - Variantes dark mode
  - Cores semânticas: `success`, `warning`, `info`, `muted`
- [ ] `[SHARED]` `shared/theme/app_typography.dart`:
  - Font family via Google Fonts (Inter ou similar)
  - Escala tipográfica: `displayLarge` → `bodySmall` + `labelSmall`
  - Sem strings mágicas — constantes para todos os tamanhos
- [ ] `[SHARED]` `shared/theme/app_spacing.dart`:
  - Constantes de padding: `xs(4)`, `sm(8)`, `md(16)`, `lg(24)`, `xl(32)`, `xxl(48)`
  - Border radius: `sm(8)`, `md(12)`, `lg(16)`, `full(999)`
- [ ] `[SHARED]` `shared/theme/app_theme.dart`:
  - `ThemeData` completo para light e dark mode
  - Seed color, `ColorScheme`, `AppBarTheme`, `CardTheme`, `InputDecorationTheme`, `BottomNavigationBarThemeData`, `FloatingActionButtonThemeData`
- [ ] `[CORE]` `core/constants/app_constants.dart`:
  - `syncIntervalSeconds: 30`
  - `autoSaveDebounceMs: 2000`
  - `sessionTimeoutMinutes: 30`
  - `maxToolIterations: 5`
- [ ] `[CORE]` `core/constants/api_constants.dart`:
  - `baseUrl` (de env ou hardcoded para dev)
  - `connectTimeoutMs`, `receiveTimeoutMs`
- [ ] `[CONFIG]` Limpar `main.dart` — remover counter demo, aplicar `ProviderScope` + `MaterialApp.router`
- [ ] `[CONFIG]` Criar estrutura de pastas vazia para todas as features

**Dependências**: nenhuma  
**Resultado**: App roda com tema aplicado, dark mode funcional, estrutura de pastas pronta. Tela vazia estilizada.

---

## FE-1 — API Client + Auth

**Objetivo**: Dio HTTP client com interceptor JWT, secure storage para tokens, e telas de login/registro.

**Branch**: `feat/flutter-auth`

### Entregáveis

- [ ] `[CORE]` `core/api/api_client.dart`:
  - Dio instance configurado (base URL, timeouts, content-type JSON)
  - Log interceptor para debug
- [ ] `[CORE]` `core/api/auth_interceptor.dart`:
  - Injeta `Authorization: Bearer <access_token>` em todas as requests
  - Se recebe 401, tenta refresh automático com o refresh token
  - Se refresh falha, redireciona para login
- [ ] `[CORE]` `core/api/api_exceptions.dart`:
  - Classes: `ApiException`, `UnauthorizedException`, `NetworkException`, `ServerException`
  - Parseia `{ "error": "message" }` do backend
- [ ] `[FEAT]` `features/auth/data/auth_local_storage.dart`:
  - Salva/lê `accessToken`, `refreshToken`, `userId` no `FlutterSecureStorage`
  - Método `clear()` para logout
- [ ] `[FEAT]` `features/auth/data/auth_repository.dart`:
  - `register(email, password, name)` → chama API, salva tokens
  - `login(email, password)` → chama API, salva tokens
  - `refresh()` → troca refresh por novo par
  - `logout()` → chama API, limpa storage
  - `isAuthenticated` → verifica se tem token válido
- [ ] `[FEAT]` `features/auth/domain/auth_state.dart`:
  - `AuthState`: `initial`, `authenticated(userId)`, `unauthenticated`
  - Riverpod `AsyncNotifier` para gerenciar estado global de auth
- [ ] `[FEAT]` `features/auth/presentation/login_screen.dart`:
  - Campos: email, senha
  - Botões: Login, "Criar conta" (navega para register)
  - Validação de formulário
  - Loading state no botão
  - Tratamento de erro (snackbar)
- [ ] `[FEAT]` `features/auth/presentation/register_screen.dart`:
  - Campos: nome, email, senha, confirmar senha
  - Mesmos padrões do login
- [ ] `[FEAT]` `features/auth/presentation/widgets/auth_form_field.dart`:
  - `TextFormField` estilizado com o design system
  - Suporte a obscureText, prefixIcon, suffixIcon
- [ ] `[FEAT]` `features/auth/presentation/widgets/auth_button.dart`:
  - Botão primário com loading indicator integrado
- [ ] `[CORE]` `core/router/app_router.dart`:
  - Rotas iniciais: `/login`, `/register`, `/home`
  - Redirect guard: se não autenticado → `/login`
- [ ] `[CORE]` `core/router/auth_guard.dart`:
  - `GoRouter.redirect` baseado no `AuthState`
- [ ] `[CORE]` `core/di/providers.dart`:
  - Providers globais: `apiClientProvider`, `authRepositoryProvider`, `authStateProvider`

**Dependências**: FE-0, Backend Feature 1 (auth API funcional)  
**Resultado**: Login e registro funcionais. Token JWT persistido. Refresh automático transparente. Rotas protegidas.

---

## FE-2 — Drift Database (SQLite Local)

**Objetivo**: Schema Drift espelhando PostgreSQL para notas, tasks, contexts e tags. DAOs com queries reativas (streams).

**Branch**: `feat/flutter-drift`

### Entregáveis

- [ ] `[CORE]` `core/database/tables/local_notes.dart`:
  ```dart
  class LocalNotes extends Table {
    TextColumn get id => text()();
    TextColumn get userId => text()();
    TextColumn get contextId => text().nullable()();
    TextColumn get title => text().nullable()();
    TextColumn get content => text()();
    TextColumn get excerpt => text().nullable()();
    BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
    BoolColumn get favorite => boolean().withDefault(const Constant(false))();
    BoolColumn get archived => boolean().withDefault(const Constant(false))();
    DateTimeColumn get createdAt => dateTime()();
    DateTimeColumn get updatedAt => dateTime()();
    DateTimeColumn get deletedAt => dateTime().nullable()();
    BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

    @override
    Set<Column> get primaryKey => {id};
  }
  ```
- [ ] `[CORE]` `core/database/tables/local_tasks.dart`:
  - Colunas: `id`, `noteId`, `userId`, `title`, `status` (open/done), `position`, `dueDate`, `completedAt`, `recurrence`, `createdAt`, `updatedAt`, `deletedAt`, `isDirty`
- [ ] `[CORE]` `core/database/tables/local_contexts.dart`:
  - Colunas: `id`, `userId`, `slug`, `name`, `createdAt`, `isDirty`
- [ ] `[CORE]` `core/database/tables/local_tags.dart`:
  - Colunas: `id`, `userId`, `name`, `isDirty`
  - Tabela de junção `local_note_tags` (noteId, tagId)
- [ ] `[CORE]` `core/database/app_database.dart`:
  - `@DriftDatabase(tables: [LocalNotes, LocalTasks, LocalContexts, LocalTags, LocalNoteTags])`
  - Schema version management com `MigrationStrategy`
- [ ] `[CORE]` `core/database/daos/notes_dao.dart`:
  - `watchAllNotes(userId)` → `Stream<List<LocalNote>>` (exclui inbox, exclui deletados)
  - `watchInboxNote(userId)` → `Stream<LocalNote?>`
  - `watchNotesByContext(userId, contextId)` → `Stream<List<LocalNote>>`
  - `watchFavorites(userId)` → `Stream<List<LocalNote>>`
  - `getNoteById(id)` → `Future<LocalNote?>`
  - `insertNote(note)` / `updateNote(note)` / `softDeleteNote(id)`
  - `getDirtyNotes()` → `Future<List<LocalNote>>` (para sync push)
  - `clearDirtyFlag(id)` → marca isDirty=false após sync
  - `upsertFromRemote(note)` → insere ou atualiza vindo do pull (sem marcar dirty)
- [ ] `[CORE]` `core/database/daos/tasks_dao.dart`:
  - `watchTasksByNote(noteId)` → `Stream<List<LocalTask>>` (ordenadas por position)
  - `watchTodayTasks(userId)` → `Stream<List<LocalTask>>` (due_date = hoje ou atrasadas)
  - `watchOpenTasks(userId)` → `Stream<List<LocalTask>>`
  - `insertTask(task)` / `updateTask(task)` / `softDeleteTask(id)`
  - `completeTask(id)`:
    - Se tem `recurrence` → marca done, cria nova entry com due_date futura, marca dirty
    - Se não → marca done, marca dirty
  - `reopenTask(id)`
  - `getDirtyTasks()` / `clearDirtyFlag(id)` / `upsertFromRemote(task)`
- [ ] `[CORE]` `core/database/daos/contexts_dao.dart`:
  - `watchContexts(userId)` → `Stream<List<LocalContext>>`
  - CRUD + dirty flag methods
- [ ] `[CORE]` `core/database/daos/tags_dao.dart`:
  - `watchTags(userId)` → `Stream<List<LocalTag>>`
  - `watchTagsForNote(noteId)` → `Stream<List<LocalTag>>`
  - CRUD + dirty flag methods
- [ ] `[CONFIG]` Rodar `dart run build_runner build` para gerar código Drift

**Dependências**: FE-0  
**Resultado**: Banco local funcional com queries reativas. Todas as operações CRUD marcam `isDirty=true`. Schema espelha PostgreSQL.

---

## FE-3 — SyncService + Connectivity

**Objetivo**: Serviço de sincronização em background que faz push de registros dirty e pull de atualizações remotas. Monitor de conectividade.

**Branch**: `feat/flutter-sync`

### Entregáveis

- [ ] `[CORE]` `core/sync/connectivity_monitor.dart`:
  - Usa `connectivity_plus` para observar estado de rede
  - Expõe `Stream<ConnectivityStatus>` (online/offline)
  - Riverpod provider: `connectivityProvider`
- [ ] `[CORE]` `core/sync/sync_state.dart`:
  - `SyncStatus`: `idle`, `syncing`, `error(message)`, `offline`
  - `lastSyncedAt`: `DateTime?` persistido no shared preferences
- [ ] `[CORE]` `core/sync/sync_service.dart`:
  - **Push**: coleta registros dirty de todos os DAOs → envia para `POST /api/v1/sync/push` → limpa dirty flags
  - **Pull**: chama `POST /api/v1/sync/pull` com `lastSyncedAt` → faz upsert local de cada registro → atualiza `lastSyncedAt`
  - **Paginação no pull**: usa `limit` + `cursor` para não baixar tudo de uma vez (primeira abertura)
  - **Triggers automáticos**:
    1. Ao abrir o app (push → pull)
    2. Ao reconectar (push → pull)
    3. Periodicamente a cada 30s enquanto online
  - **Soft delete**: registros com `deletedAt` são sincronizados mas não exibidos na UI
  - **Ordem**: sempre push primeiro, depois pull (evita sobrescrever mudanças locais)
  - Riverpod provider: `syncServiceProvider`
- [ ] `[SHARED]` `shared/widgets/offline_banner.dart`:
  - Banner sutil no topo do app quando offline
  - Texto: "Você está offline. Suas alterações serão sincronizadas quando a conexão voltar."
  - Ícone de nuvem riscada
  - Animação de entrada/saída suave
- [ ] `[CORE]` Integrar sync no `main.dart`:
  - Iniciar sync service após login bem-sucedido
  - Parar ao fazer logout
  - Registrar listener de connectivity para trigger de reconexão

**Dependências**: FE-1 (auth para ter userId e tokens), FE-2 (Drift DAOs), Backend Feature 11 (sync API)  
**Resultado**: Sync automático funcional. App funciona offline para CRUD. Banner de offline visível.

---

## FE-4 — Home + Lista de Notas

**Objetivo**: Tela principal com navegação por tabs/drawer, listagem de notas reativa (do Drift local), filtros por contexto e favoritas.

**Branch**: `feat/flutter-home`

### Entregáveis

- [ ] `[FEAT]` `features/notes/domain/note_model.dart`:
  - Model puro (`NoteModel`) com factory para converter de/para `LocalNote`
  - Campos: id, title, excerpt, isInbox, favorite, archived, contextId, createdAt, updatedAt
- [ ] `[FEAT]` `features/notes/data/local/notes_local_source.dart`:
  - Wrapper fino sobre `NotesDao` para a camada de features
  - Expõe streams e futures tipados com `NoteModel`
- [ ] `[FEAT]` `features/notes/domain/notes_repository.dart`:
  - `watchNotes({contextId?, favoritesOnly?})` → `Stream<List<NoteModel>>`
  - `watchInbox()` → `Stream<NoteModel?>`
  - `createNote(title, content, contextId?)` → cria local com `isDirty=true`
  - `updateNote(id, {title?, content?, favorite?, archived?})`
  - `deleteNote(id)` → soft delete local
- [ ] `[FEAT]` `features/notes/presentation/notes_list_screen.dart`:
  - Lista de notas em cards (`NoteCard`)
  - Pull-to-refresh (trigger sync manual)
  - Ordenação: mais recentes primeiro (`updatedAt DESC`)
  - Empty state quando não tem notas
  - FAB de captura rápida (bottom-right)
- [ ] `[FEAT]` `features/notes/presentation/widgets/note_card.dart`:
  - Título em negrito + excerpt (max 2 linhas)
  - Badge de favorita (estrela)
  - Indicador de contexto (chip colorido)
  - Timestamp relativo (`timeago`)
  - Swipe-to-delete com confirmação
  - Tap → navega para editor
  - Long press → menu de ações (favoritar, mover contexto, deletar)
- [ ] `[FEAT]` `features/notes/presentation/widgets/quick_capture_fab.dart`:
  - FAB sempre visível na lista de notas
  - Tap → abre bottom sheet com campo de texto
  - Salva direto no inbox note (local, `isDirty=true`)
  - Dismiss ao salvar com feedback visual (snackbar "Salvo no rascunho")
- [ ] `[CORE]` Navegação principal (bottom navigation ou drawer):
  - **Notas** (lista de notas)
  - **Hoje** (tasks do dia)
  - **Chat** (agent)
  - **Busca** (search)
  - Atualizar `app_router.dart` com nested navigation
- [ ] `[SHARED]` `shared/widgets/empty_state.dart`:
  - Widget genérico com ícone, título e descrição
  - Usado em notas, tasks, search, etc.

**Dependências**: FE-0, FE-2  
**Resultado**: Home funcional com lista de notas reativa. FAB de captura rápida. Navegação entre tabs.

---

## FE-5 — Editor de Notas (super_editor)

**Objetivo**: Editor Markdown completo com super_editor, auto-save com debounce, toolbar contextual, e tela do inbox com botão "Organizar".

**Branch**: `feat/flutter-editor`

### Entregáveis

- [ ] `[FEAT]` `features/notes/presentation/note_editor_screen.dart`:
  - Parâmetro: `noteId` (edita existente) ou `null` (cria nova)
  - super_editor com documento Markdown
  - Título editável no topo (fora do editor, como Apple Notes)
  - Toolbar no topo: bold, italic, heading, list, checklist
  - Auto-save: debounce de 2s após última mudança
    - Converte documento super_editor → Markdown string
    - Salva no Drift local com `isDirty=true`
  - Botão de favoritar na AppBar
  - Indicador "Salvo" / "Salvando..." sutil
  - Botão voltar salva automaticamente
- [ ] `[FEAT]` `features/notes/presentation/widgets/note_toolbar.dart`:
  - Barra flutuante abaixo do título
  - Ícones: **B**, *I*, H1, H2, bullet list, numbered list, checklist, quote
  - Reflete estado atual do cursor (negrito ativo = ícone destacado)
  - Animação de slide-in quando teclado abre
- [ ] `[FEAT]` Editor ↔ Markdown conversion:
  - Markdown → `MutableDocument` (parse para abrir nota)
  - `MutableDocument` → Markdown string (serialização para salvar)
  - Tasks no documento são renderizadas como checkboxes interativos (via custom ComponentBuilder do super_editor)
- [ ] `[FEAT]` `features/notes/presentation/inbox_screen.dart`:
  - Igual ao editor mas com comportamento especial:
    - Título fixo "Rascunho" (não editável)
    - Botão "Organizar" na AppBar (só aparece se tem conteúdo)
    - Não mostra opção de deletar/arquivar
    - Acesso direto da home (card especial no topo ou seção dedicada)
- [ ] `[FEAT]` `features/notes/presentation/widgets/inbox_organize_sheet.dart`:
  - Bottom sheet que aparece ao clicar "Organizar"
  - Estado: loading → mostra plano proposto pelo agent
  - Cada item do plano com:
    - Trecho original
    - Destino proposto (nota existente / nova nota / manter no rascunho)
    - Toggle para aceitar/rejeitar individualmente
  - Botões: "Aplicar selecionados" / "Cancelar"
  - Chama `POST /api/v1/notes/inbox/organize/plan` → exibe → `POST /api/v1/notes/inbox/organize/apply`
- [ ] `[FEAT]` Custom super_editor `ComponentBuilder` para tasks:
  - Renderiza tasks do banco como checkbox widgets inline no editor
  - Tap no checkbox → atualiza task no Drift (complete/reopen)
  - Mostra due_date ao lado quando existir

**Dependências**: FE-2, FE-4  
**Resultado**: Editor completo com auto-save. Inbox com organização assistida por IA. Tasks interativas no editor.

---

## FE-6 — Tasks (Tela "Hoje" + Widgets)

**Objetivo**: Tela dedicada para tasks do dia, e widgets reutilizáveis de task (checkbox, tile, pickers).

**Branch**: `feat/flutter-tasks`

### Entregáveis

- [ ] `[FEAT]` `features/tasks/domain/task_model.dart`:
  - Model puro com factory para converter de/para `LocalTask`
  - Campos: id, noteId, title, status, position, dueDate, completedAt, recurrence, createdAt, updatedAt
  - Computed: `isOverdue`, `isDueToday`, `isRepeating`
- [ ] `[FEAT]` `features/tasks/data/local/tasks_local_source.dart`:
  - Wrapper sobre `TasksDao` com tipos `TaskModel`
- [ ] `[FEAT]` `features/tasks/domain/tasks_repository.dart`:
  - `watchTodayTasks()` → `Stream<List<TaskModel>>` (today + overdue, ordenadas por due_date)
  - `watchTasksByNote(noteId)` → `Stream<List<TaskModel>>` (ordenadas por position)
  - `createTask(noteId, title, {dueDate?, recurrence?})`
  - `completeTask(id)` — lógica de recorrência local:
    - Salva completion, reabre com nova due_date baseada na recurrence
  - `reopenTask(id)`
  - `updateTask(id, {title?, dueDate?, recurrence?, position?})`
  - `deleteTask(id)` → soft delete
- [ ] `[FEAT]` `features/tasks/presentation/today_screen.dart`:
  - Seções:
    - **Atrasadas** (due_date < hoje, vermelhas)
    - **Hoje** (due_date = hoje)
    - **Sem data** (tasks abertas sem due_date, seção colapsável)
  - Cada task é um `TaskTile` com checkbox
  - Empty state: "Nenhuma task para hoje 🎉"
  - FAB: criar task rápida (bottom sheet com título + opcional due_date)
- [ ] `[FEAT]` `features/tasks/presentation/note_tasks_list.dart`:
  - Widget embeddable na tela de nota
  - Lista de tasks da nota específica
  - Drag to reorder (atualiza `position`)
  - Botão "+" para adicionar task inline
- [ ] `[FEAT]` `features/tasks/presentation/widgets/task_checkbox.dart`:
  - Checkbox animado (checked → strikethrough no título com fade)
  - Ícone de repetição quando `isRepeating` (🔁 sutil)
- [ ] `[FEAT]` `features/tasks/presentation/widgets/task_tile.dart`:
  - Layout: checkbox + título + due_date badge + recurrence icon
  - Due date badge: verde (hoje), vermelho (atrasada), cinza (futura)
  - Swipe-right: complete. Swipe-left: delete
  - Tap: edita (bottom sheet com campos)
- [ ] `[FEAT]` `features/tasks/presentation/widgets/due_date_picker.dart`:
  - Atalhos: "Hoje", "Amanhã", "Próxima segunda", "Escolher data"
  - Date picker nativo do Flutter ao escolher data custom
- [ ] `[FEAT]` `features/tasks/presentation/widgets/recurrence_picker.dart`:
  - Opções: Nenhuma, Diária, Dias úteis, Semanal, Mensal
  - Chips selecionáveis com ícone

**Dependências**: FE-2, FE-4  
**Resultado**: Tela "Hoje" funcional. Tasks interativas com checkbox, due dates, e recorrência.

---

## FE-7 — Agent Chat (SSE Streaming)

**Objetivo**: Interface de chat com o agent backend, consumindo SSE para streaming de respostas em tempo real.

**Branch**: `feat/flutter-chat`

### Entregáveis

- [ ] `[FEAT]` `features/agent/domain/message_model.dart`:
  - `MessageModel`: id, role (user/assistant), content, createdAt
  - `MessageListState`: lista de mensagens + isStreaming flag
- [ ] `[FEAT]` `features/agent/domain/session_manager.dart`:
  - Gera `session_id` (UUID) ao abrir chat pela primeira vez
  - Detecta se app ficou em background >30 minutos → gera novo session_id
  - Botão "Nova conversa" → gera novo session_id
  - Persiste session_id (memory, não storage — efêmero)
- [ ] `[FEAT]` `features/agent/data/sse_client.dart`:
  - Consome SSE via Dio com `ResponseType.stream`
  - Parseia `data: {"delta": "..."}` e `data: {"done": true}`
  - Expõe `Stream<String>` de chunks
  - ~30 linhas conforme escopo
- [ ] `[FEAT]` `features/agent/data/agent_repository.dart`:
  - `sendMessage(content, sessionId)` → chama `POST /api/v1/agent/chat/stream`
  - Retorna `Stream<String>` para streaming
  - `getHistory(limit)` → `GET /api/v1/agent/messages`
  - `clearHistory()` → `DELETE /api/v1/agent/messages`
- [ ] `[FEAT]` `features/agent/presentation/chat_screen.dart`:
  - Lista de mensagens scrollável (newest at bottom)
  - Auto-scroll para baixo ao receber nova mensagem
  - Input de texto na parte inferior com botão enviar
  - Indicador "pensando" enquanto aguarda primeira chunk
  - Streaming: mensagem do assistant cresce em tempo real
  - AppBar: título "Chat" + botão "Nova conversa"
  - Feature online-only: mostra estado desabilitado quando offline
- [ ] `[FEAT]` `features/agent/presentation/widgets/message_bubble.dart`:
  - Bubble do usuário: alinhada à direita, cor primária
  - Bubble do assistant: alinhada à esquerda, cor de superfície
  - Renderiza Markdown dentro da bubble (code blocks, bold, italic, listas)
  - Animação de fade-in suave
- [ ] `[FEAT]` `features/agent/presentation/widgets/chat_input.dart`:
  - TextField multi-line (expande até 4 linhas)
  - Botão de enviar (ícone send)
  - Desabilitado durante streaming (enquanto agent responde)
  - Ctrl+Enter / button para enviar
- [ ] `[FEAT]` `features/agent/presentation/widgets/typing_indicator.dart`:
  - 3 pontos animados (bounce animation)
  - Aparece enquanto aguarda primeira chunk do SSE
- [ ] `[FEAT]` `features/agent/presentation/widgets/new_session_button.dart`:
  - Ícone na AppBar
  - Confirmação: "Iniciar nova conversa?"
  - Limpa mensagens visíveis, gera novo session_id

**Dependências**: FE-0, FE-1 (auth), Backend Feature 6 (agent API)  
**Resultado**: Chat funcional com streaming em tempo real. Sessões gerenciadas automaticamente. Markdown renderizado nas respostas.

---

## FE-8 — Busca (FTS + Semântica + Híbrida)

**Objetivo**: Tela de busca com debounce, modos de busca, e resultados navegáveis.

**Branch**: `feat/flutter-search`

### Entregáveis

- [ ] `[FEAT]` `features/search/domain/search_result_model.dart`:
  - `SearchResultModel`: noteId, title, excerpt, score, mode
- [ ] `[FEAT]` `features/search/data/search_repository.dart`:
  - `search(query, mode)` → chama `POST /api/v1/search`
  - Retorna `List<SearchResultModel>`
- [ ] `[FEAT]` `features/search/presentation/search_screen.dart`:
  - Search bar no topo com auto-focus
  - Debounce de 300ms antes de enviar query
  - Lista de resultados (`SearchResultTile`)
  - Empty state: "Nenhum resultado" ou "Digite para buscar"
  - Tap no resultado → navega para o editor da nota
  - Feature online-only com indicador visual
- [ ] `[FEAT]` `features/search/presentation/widgets/search_bar.dart`:
  - TextField estilizado com ícone de busca e botão clear
  - Debounce integrado (Timer)
- [ ] `[FEAT]` `features/search/presentation/widgets/search_result_tile.dart`:
  - Título em bold + excerpt com highlight do termo buscado
  - Badge do modo usado (FTS/Semântica/Híbrida)
  - Score de relevância sutil
- [ ] `[FEAT]` `features/search/presentation/widgets/search_mode_toggle.dart`:
  - SegmentedButton com 3 opções: Texto, Semântica, Híbrida
  - Default: Híbrida (recommended)
  - Tooltip explicando cada modo

**Dependências**: FE-0, FE-1, Backend Feature 7 (search API)  
**Resultado**: Busca funcional nos 3 modos. Resultados linkam para o editor da nota.

---

## FE-9 — Settings + SOUL + Contextos

**Objetivo**: Telas de configuração seguindo a hierarquia definida no escopo (Conta, Notificações, Avançado).

**Branch**: `feat/flutter-settings`

### Entregáveis

- [ ] `[FEAT]` `features/settings/presentation/settings_screen.dart`:
  - Estrutura:
    ```
    Conta (email, nome, logout)
    Notificações (FCM toggle — v1 simples)
    Avançado
    ├── Personalidade do agent → SoulEditorScreen
    ├── Contextos → ContextsScreen
    └── Dados (info sobre sync, limpar cache)
    ```
  - Usa `SettingsTile` para cada item
- [ ] `[FEAT]` `features/settings/presentation/widgets/settings_tile.dart`:
  - ListTile estilizado com ícone, título, subtítulo, trailing
  - Variantes: navigation (chevron), toggle (switch), action (botão)
- [ ] `[FEAT]` `features/settings/presentation/soul_editor_screen.dart`:
  - Campo de texto multi-line (Markdown)
  - Carrega SOUL via `GET /api/v1/soul`
  - Salva via `PUT /api/v1/soul`
  - Botão "Restaurar padrão" com confirmação
  - Preview do Markdown renderizado (toggle view/edit)
- [ ] `[FEAT]` `features/settings/presentation/contexts_screen.dart`:
  - Lista de contextos (pastas) do usuário
  - Criar novo contexto (bottom sheet com nome)
  - Deletar contexto (swipe + confirmação)
  - Feature online-only
- [ ] `[FEAT]` `features/settings/data/settings_repository.dart`:
  - `getSettings()` / `updateSettings(timezone)`
  - `getSoul()` / `updateSoul(content)`
  - `getContexts()` / `createContext(name)` / `deleteContext(id)`
- [ ] `[SHARED]` `shared/widgets/confirm_dialog.dart`:
  - Dialog genérico de confirmação com título, descrição, botão confirmar (destrutivo), botão cancelar

**Dependências**: FE-0, FE-1, Backend Features 4 (soul), 12 (settings)  
**Resultado**: Settings navegáveis. SOUL editável. Contextos gerenciáveis.

---

## FE-10 — Rotinas (Briefs Schedule + Histórico)

**Objetivo**: UI para configurar agenda dos briefs e ver histórico de execuções.

**Branch**: `feat/flutter-routines`

### Entregáveis

- [ ] `[FEAT]` `features/routines/domain/routine_model.dart`:
  - `RoutineModel`: id, briefType, name, daysOfWeek, timeOfDay, enabled, lastRunAt
- [ ] `[FEAT]` `features/routines/domain/routine_log_model.dart`:
  - `RoutineLogModel`: id, routineId, output (Markdown), telegramSentAt, createdAt
- [ ] `[FEAT]` `features/routines/data/routines_repository.dart`:
  - `getRoutines()` → `List<RoutineModel>`
  - `updateDailySchedule(days, time, enabled)` → `PATCH /api/v1/routines/daily`
  - `updateWeeklySchedule(day, time, enabled)` → `PATCH /api/v1/routines/weekly`
  - `testBrief(type)` → `POST /api/v1/routines/{type}/test`
  - `getLogs()` → `List<RoutineLogModel>`
- [ ] `[FEAT]` `features/routines/presentation/routines_screen.dart`:
  - Dois cards (`BriefScheduleCard`): Daily e Weekly
  - Botão "Ver histórico" → navega para `BriefHistoryScreen`
  - Feature online-only
- [ ] `[FEAT]` `features/routines/presentation/widgets/brief_schedule_card.dart`:
  - Layout conforme escopo:
    ```
    Brief diário
    [Switch] Ativo
    Dias: [DaySelector]
    Horário: [TimePickerField]
    [Botão Testar]
    ```
  - Testar: mostra resultado em dialog/bottom sheet (Markdown renderizado)
- [ ] `[FEAT]` `features/routines/presentation/widgets/day_selector.dart`:
  - Chips para Seg–Dom
  - Daily: multi-select (mínimo 1)
  - Weekly: single-select (exatamente 1)
- [ ] `[FEAT]` `features/routines/presentation/widgets/time_picker_field.dart`:
  - Mostra horário selecionado + ícone de relógio
  - Tap → `showTimePicker()` nativo
- [ ] `[FEAT]` `features/routines/presentation/brief_history_screen.dart`:
  - Lista de `RoutineLogModel` em ordem cronológica reversa
  - Cada item: data/hora + preview do output
  - Tap → expande para ver output completo (Markdown renderizado)
  - Indicador se foi enviado via Telegram
- [ ] `[FEAT]` `features/routines/presentation/widgets/brief_log_tile.dart`:
  - Data/hora formatada
  - Preview (primeiras 2 linhas)
  - Ícone de Telegram quando `telegramSentAt` não é null

**Dependências**: FE-0, FE-1, Backend Feature 8 (routines API)  
**Resultado**: Briefs configuráveis pela UI. Histórico visualizável. Teste dry-run funcional.

---

## FE-11 — Telegram Link

**Objetivo**: Fluxo de vinculação do Telegram na tela de settings.

**Branch**: `feat/flutter-telegram`

### Entregáveis

- [ ] `[FEAT]` `features/settings/presentation/telegram_link_screen.dart`:
  - Estado 1 — **Não vinculado**:
    - Botão "Conectar Telegram"
    - Gera código via `POST /api/v1/telegram/link-code`
    - Mostra código em destaque (copiável)
    - Instruções: "Abra @notes_agent_bot no Telegram e envie: `/start CÓDIGO`"
    - Timer visual de expiração do código
    - Polling sutil para verificar se vínculo foi feito (ou WebSocket futuro)
  - Estado 2 — **Vinculado**:
    - Mostra username do Telegram
    - Botão "Desconectar" com confirmação
    - `DELETE /api/v1/telegram/link`
- [ ] `[FEAT]` `features/settings/presentation/widgets/telegram_status_badge.dart`:
  - Badge na tela de settings: "Conectado" (verde) ou "Não conectado" (cinza)
- [ ] `[FEAT]` Integrar na `settings_screen.dart` como item de Settings

**Dependências**: FE-9, Backend Feature 9 (Telegram API)  
**Resultado**: Fluxo completo de vincular/desvincular Telegram pelo app.

---

## FE-12 — Polish, Animações e Error Handling

**Objetivo**: Micro-animações, tratamento global de erros, loading states, e refinamentos de UX.

**Branch**: `feat/flutter-polish`

### Entregáveis

- [ ] `[SHARED]` `shared/widgets/loading_overlay.dart`:
  - Overlay semi-transparente com CircularProgressIndicator
  - Usado em operações assíncronas que bloqueiam UI (aplicar plano de organização, etc.)
- [ ] `[SHARED]` `shared/widgets/error_snackbar.dart`:
  - Snackbar estilizado para erros de API
  - Ícone de erro + mensagem + botão "Tentar novamente" quando aplicável
- [ ] `[SHARED]` `shared/widgets/markdown_renderer.dart`:
  - Widget que renderiza Markdown para uso em:
    - Bubbles do chat
    - Preview do SOUL
    - Output de briefs
    - Resultado de busca
- [ ] `[FEAT]` Animações e transições:
  - Hero animation na note_card → note_editor (título)
  - Fade transition entre tabs do bottom navigation
  - Slide-up do bottom sheet de captura rápida
  - Animated checkbox (scale + color transition)
  - Shimmer loading em listas enquanto carrega
- [ ] `[FEAT]` Error handling global:
  - Riverpod `ProviderObserver` para logging de erros
  - `ErrorBoundary` widget para erros em build
  - Retry automático em erros de rede (com exponential backoff)
  - Mensagens amigáveis para erros comuns:
    - Sem conexão → "Você está offline"
    - Timeout → "O servidor demorou para responder"
    - 500 → "Algo deu errado. Tente novamente."
    - 401 → redirect para login
- [ ] `[FEAT]` Loading states em todas as telas:
  - Lista de notas: shimmer cards
  - Editor: loading spinner ao abrir nota grande
  - Chat: typing indicator
  - Search: skeleton results
  - Settings: loading spinner em saves
- [ ] `[FEAT]` Empty states em todas as telas:
  - Notas: "Crie sua primeira nota" + ilustração
  - Tasks hoje: "Nenhuma task para hoje 🎉"
  - Chat: "Inicie uma conversa com seu agent"
  - Search: "Busque em todas as suas notas"
  - Briefs: "Nenhum brief gerado ainda"
- [ ] `[CONFIG]` App icon e splash screen:
  - Ícone do app (logo SupaNotes)
  - Splash screen com logo + cor primária
  - Usar `flutter_launcher_icons` e `flutter_native_splash`
- [ ] `[FEAT]` FCM integration:
  - Registrar device token no backend ao fazer login
  - Receber push notification → navegar para brief history

**Dependências**: todas as features FE anteriores  
**Resultado**: App polido com animações suaves, error handling robusto, e UX premium.

---

## Ordem de Execução

```
FE-0   → Design System + Configuração
FE-1   → API Client + Auth
FE-2   → Drift Database (pode ser paralelo com FE-1)
FE-3   → SyncService + Connectivity
FE-4   → Home + Lista de Notas
FE-5   → Editor de Notas (super_editor)
FE-6   → Tasks (Tela Hoje + Widgets)
FE-7   → Agent Chat (SSE)
FE-8   → Busca
FE-9   → Settings + SOUL + Contextos
FE-10  → Rotinas (Briefs)
FE-11  → Telegram Link
FE-12  → Polish + Animações + Error Handling
```

---

## Dependências do Backend por Feature

| Feature Flutter | Funciona sem backend? | APIs necessárias |
|---|---|---|
| FE-0 Design System | ✅ Sim | — |
| FE-1 Auth | ❌ | `POST /auth/*` |
| FE-2 Drift | ✅ Sim | — |
| FE-3 Sync | ❌ | `POST /sync/pull`, `/sync/push` |
| FE-4 Home + Notas | ✅ Parcial (lista local) | — (sync para remote) |
| FE-5 Editor | ✅ Parcial (auto-save local) | `POST /notes/inbox/organize/*` |
| FE-6 Tasks | ✅ Parcial (CRUD local) | — (sync para remote) |
| FE-7 Chat | ❌ | `POST /agent/chat/stream`, `GET /agent/messages` |
| FE-8 Busca | ❌ | `POST /search` |
| FE-9 Settings | ❌ | `GET/PUT /settings`, `GET/PUT /soul`, `GET/POST/DELETE /contexts` |
| FE-10 Rotinas | ❌ | `GET/PATCH /routines/*`, `GET /routines/logs` |
| FE-11 Telegram | ❌ | `GET/POST/DELETE /telegram/*` |
| FE-12 Polish | ✅ Sim | — |

> **Dica**: FE-0, FE-2, FE-4 (lista local), FE-5 (editor local), FE-6 (tasks local) e FE-12 podem ser desenvolvidas antes do backend estar pronto, usando dados mockados no Drift.

---

## Estimativa

| Feature | Complexidade | Estimativa |
|---|---|---|
| FE-0 Design System | Baixa | 1 dia |
| FE-1 Auth | Média | 2 dias |
| FE-2 Drift | Alta | 2–3 dias |
| FE-3 Sync | Alta | 2–3 dias |
| FE-4 Home + Notas | Média | 2 dias |
| FE-5 Editor (super_editor) | **Muito alta** | 4–5 dias |
| FE-6 Tasks | Alta | 2–3 dias |
| FE-7 Chat (SSE) | Alta | 2–3 dias |
| FE-8 Busca | Baixa | 1 dia |
| FE-9 Settings | Média | 1–2 dias |
| FE-10 Rotinas | Média | 1–2 dias |
| FE-11 Telegram | Baixa | 1 dia |
| FE-12 Polish | Alta | 2–3 dias |
| **Total** | | **~22–30 dias** |

> **Nota**: FE-5 (editor) é a feature mais complexa do frontend. A integração do super_editor com Markdown parsing/serialization e custom component builders para tasks exige atenção especial.

---

## Referências

- [Escopo técnico v3 — §4 Estrutura Flutter](SuperNotes/notes-agent-scope-v3.md)
- [Escopo técnico v3 — §22 Simplicidade de uso](SuperNotes/notes-agent-scope-v3.md)
- [Escopo técnico v3 — §23 Arquitetura local-first](SuperNotes/notes-agent-scope-v3.md)
- [Glossário de domínio](SuperNotes/CONTEXT.md)
- [Roadmap geral](ROADMAP.md)
- [Convenções do projeto](agents.md)
