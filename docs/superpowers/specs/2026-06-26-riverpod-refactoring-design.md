# Riverpod Refactoring — Design Doc

> **Goal:** Migrate all Riverpod anti-patterns identified in the 2026-06-26 audit to follow the Flutter Riverpod Expert 2025 Best Practices skill.

**Scope:** Big Bang — all violations in a single pass.
**Strategy:** Rewrite providers then fix consumers. No codegen — manual providers only (project convention).

---

## 1. `Notifier<AsyncValue<T>>` → `AsyncNotifier<T>`

### 1.1 `AuthController` (causa raiz de ~15 violações)

| Hoje | Depois |
|------|--------|
| `class AuthController extends Notifier<AsyncValue<User?>>` | `class AuthController extends AsyncNotifier<User?>` |
| `AsyncValue<User?> build()` | `Future<User?> build()` |
| `state = const AsyncValue.loading()` | Gerenciado pelo `AsyncNotifier` |
| `state = AsyncValue.data(user)` | `state = AsyncValue.data(user)` (igual) |
| `state = AsyncValue.error(e, st)` | `state = AsyncValue.error(e, st)` (igual) |
| `ref.read(authControllerProvider).isLoading` nas telas | `ref.watch(authControllerProvider).when(...)` |

**Mudanças no provider:**
- `build()` agora é `Future<User?> build()` — async, retorna `null` se não logado
- `_restore()` vira lógica inline do `build()`: carrega token, se não existir retorna `null`
- `login()`/`register()` continuam settando `state = AsyncValue.data(user)` e `AsyncValue.error(e, st)`
- `logout()` continua settando `state = const AsyncValue.data(null)` + invalida dependentes

**Mudanças nos consumers:**
- `current_user.dart:9`: `ref.watch(authControllerProvider.select((u) => u.valueOrNull?.id))` — usa `select` em vez de `.asData?.value`
- `login_screen.dart:42,61-63`: Substitui `ref.read(...).isLoading` por `_submit()` sem guard e usa `authControllerProvider.when()` no build
- `register_screen.dart:45,65-67`: Idem
- `settings_screen.dart:28`: `authControllerProvider.when(data:(u) => u, ...)` em vez de `.asData?.value`
- `settings_screen.dart:119`: `ref.watch(syncStateProvider)` em vez de `ref.read(syncStateProvider)`

### 1.2 `ChatController`

| Hoje | Depois |
|------|--------|
| `class ChatController extends Notifier<AsyncValue<ChatState>>` | `class ChatController extends AsyncNotifier<ChatState>` |
| `AsyncValue<ChatState> build()` | `Future<ChatState> build()` |
| `state = AsyncValue.data(ChatState(...))` | `state = AsyncValue.data(ChatState(...))` |
| `state = AsyncValue.error(e, st)` | `state = AsyncValue.error(e, st)` |

**Mudanças:**
- `build()` agora `Future<ChatState>` que retorna `ChatState.empty()` ou similar
- Internamente continua igual — `state` ainda é `AsyncValue<ChatState>`, só muda a declaração da classe
- `chat_screen.dart`: usa `whenOrNull(error:...)` no `ref.listen` em vez de `!next.isLoading && next.hasError`

### 1.3 `ShareNoteController`

| Hoje | Depois |
|------|--------|
| `class ShareNoteController extends Notifier<AsyncValue<void>>` | `class ShareNoteController extends AsyncNotifier<void>` |
| `AsyncValue<void> build()` | `Future<void> build()` |

**Mudanças:**
- `build()` retorna `Future<void>` — só `async` → `return;`
- `share()` continua usando `AsyncValue.guard()`
- `share_note_sheet.dart`: usa `.when()` em vez de `.isLoading` / `.hasError`

---

## 2. Logout invalida dependentes

`AuthController.logout()` agora chama `ref.invalidate(...)` para:

- `soulProvider`
- `contextsProvider`
- `routinesProvider`
- `briefHistoryProvider`
- `chatControllerProvider`
- `syncServiceProvider`
- `telegramStatusProvider`
- `memoriesControllerProvider`
- `searchResultsProvider`

---

## 3. Widgets: `.asData?.value` e booleanos locais

### 3.1 Telas com `.asData?.value`

**`note_editor_screen.dart` (linhas 67-69):**
```dart
// Antes
final tasksMap = tasksAsync.asData?.value != null
    ? {for (final t in tasksAsync.asData!.value) t.id: t}
    : const <String, TaskModel>{};

// Depois
final tasksMap = tasksAsync.when(
  data: (tasks) => {for (final t in tasks) t.id: t},
  loading: () => const <String, TaskModel>{},
  error: (_, __) => const <String, TaskModel>{},
);
```

**`inbox_screen.dart` (linhas 85-87):**
```dart
// Mesmo pattern do note_editor_screen, mesma substituição
```

**`soul_editor_screen.dart` (linha 70 + `_initialized`):**
- Elimina `bool _initialized = false`
- `_controller.text = soul.personality` dentro do `data:` do `.when()` via callback
- Ou usa `ref.listen(soulProvider, ...)` para popular o controller na inicialização

### 3.2 Booleanos locais

**`soul_editor_screen.dart:26` `_initialized`:**
- Remove o boolean. Popula o `TextEditingController` via `ref.listen(soulProvider, ...)` ou via `initState` com `ref.read(soulProvider.future).then(...)`

**`telegram_link_screen.dart:24` `_waitingForLink`:**
- Substitui por estado do `telegramPairingProvider` — o provider já tem `TelegramPairingState` com `isPairing` ou similar
- Se não tiver, adiciona campo `isWaitingForLink` ao state do `TelegramPairingController`

**`mcp_screen.dart:44` `_isGenerating`:**
- Cria `McpTokenController extends AsyncNotifier<String?>` que gerencia geração de token
- `_TokenCard` recebe o `AsyncValue<String?>` e usa `.when()`

**`task_edit_sheet.dart:71` `_saving`:**
- Mantém como local — é UI transient state aceitável (save dentro de bottom sheet, não justifica provider)

### 3.3 `ref.listen` com `.isLoading`/`.hasError`

**`chat_screen.dart:20`:**
```dart
// Antes
if (!next.isLoading && next.hasError && next.error != prev?.error)

// Depois
next.whenOrNull(error: (err, _) {
  if (prev?.error != err) AppMessenger.showError(err.toString());
});
```

**`memories_screen.dart:23`:**
```dart
// Antes
if (next.hasError && (prev == null || !prev.hasError))

// Depois
next.whenOrNull(error: (err, _) {
  if (prev == null || prev.hasError == false) AppMessenger.showError(err.toString());
});
```

---

## 4. `FutureProvider` → `AsyncNotifier`

**`soulProvider`** (já tem `soulSaveProvider` como `AsyncNotifier`):
- Muda para `AsyncNotifierProvider.autoDispose<SoulNotifier, Soul>`
- `SoulNotifier extends AsyncNotifier<Soul>` com `build()` = fetch inicial
- Mantém compatibilidade: `soulSaveProvider` invalida `soulProvider`, que refaz fetch

**`contextsProvider`, `routinesProvider`, `briefHistoryProvider`:**
- Permanecem como `FutureProvider` — são read-only queries sem mutations locais
- As mutations (delete context, etc.) chamam `ref.invalidate(provider)` diretamente
- NOTA: a skill diz "PREFERRED", não obrigatório. Para queries puramente read-only sem estado de mutation, `FutureProvider` é aceitável.

---

## 5. `select()` para performance

**`settings_screen.dart`:**
```dart
// Antes
final account = ref.watch(authControllerProvider).asData?.value;
// Depois
final account = ref.watch(authControllerProvider.select((u) => u.valueOrNull));
```

---

## 6. Robot — Providers e Telas Não Alterados

- `SyncStateNotifier`: já é `Notifier<SyncState>` — correto (síncrono)
- `SessionCacheNotifier`: já é `Notifier<SessionCache>` — correto (síncrono)
- `MemoriesController`: já é `AsyncNotifier<List<MemoryModel>>` — correto
- `SoulSaveNotifier`: já é `AsyncNotifier<void>` — correto
- `TelegramPairingController`: já é `Notifier<TelegramPairingState>` — correto (síncrono state com timer)
- `PushService`: já é `Notifier<bool>` — correto (síncrono)
- `SessionManager`: já é `Notifier<String>` — correto (síncrono)
- `searchResultsProvider`: `FutureProvider.family` — mantido (read-only query)
- Todos os `StreamProvider` (Drift streams): mantidos (real-time streams)
- `notes_list_screen.dart`, `routines_screen.dart`, `brief_history_screen.dart`, `contexts_screen.dart`: já usam `.when()` — sem alterações

---

## Risco e Rollback

**Risco principal:** `AuthController` é usado por virtualmente todas as telas. Se quebrar, o app inteiro fica inacessível.

**Mitigação:** Big Bang, mas com testes:
1. Rodar `dart analyze` após cada arquivo alterado
2. Testar manualmente: login, register, logout, navegação, chat, settings
3. Se algo quebrar, reverter commit inteiro

---

## Arquivos Alterados

### Providers (modify):
- `lib/features/auth/presentation/controllers/auth_controller.dart`
- `lib/features/agent/presentation/controllers/chat_controller.dart`
- `lib/features/notes/presentation/controllers/share_note_controller.dart`
- `lib/features/settings/presentation/controllers/soul_editor_controller.dart` (soulProvider)
- `lib/core/auth/current_user.dart`
- `lib/features/settings/presentation/controllers/contexts_controller.dart` (MANTIDO como FutureProvider)
- `lib/features/routines/presentation/controllers/routines_controller.dart` (MANTIDO como FutureProvider)

### Telas/Widgets (modify):
- `lib/core/auth/current_user.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/register_screen.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/settings/presentation/soul_editor_screen.dart`
- `lib/features/settings/presentation/mcp_screen.dart`
- `lib/features/notes/presentation/note_editor_screen.dart`
- `lib/features/notes/presentation/inbox_screen.dart`
- `lib/features/notes/presentation/widgets/share_note_sheet.dart`
- `lib/features/telegram/presentation/telegram_link_screen.dart`
- `lib/features/agent/presentation/chat_screen.dart`
- `lib/features/memories/presentation/memories_screen.dart`

### Create:
- `lib/features/settings/presentation/controllers/mcp_token_controller.dart` (se criar provider)
