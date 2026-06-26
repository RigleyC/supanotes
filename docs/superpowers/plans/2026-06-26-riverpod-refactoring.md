# Riverpod Refactoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development or executing-plans to implement this plan task-by-task.

**Goal:** Migrate all Riverpod anti-patterns to follow Flutter Riverpod Expert 2025 Best Practices: replace `Notifier<AsyncValue<T>>` with `AsyncNotifier<T>`, invalidate dependents on logout, fix `.asData?.value`/`.isLoading` widget patterns, eliminate local boolean flags for async state, and add `select()` performance optimizations.

**Architecture:** Big Bang — migrate providers first (root deps), then fix all consumers, then add optimizations.

**Tech Stack:** Flutter 3.x, Riverpod 3.x (manual providers, no codegen), Drift, Dio

---

### Task 1: Migrate `AuthController` — `Notifier<AsyncValue<User?>>` → `AsyncNotifier<User?>`

**Files:**
- Modify: `lib/features/auth/presentation/controllers/auth_controller.dart`
- Modify: `lib/core/di/providers.dart`
- Test: `test/features/auth/domain/auth_state_test.dart`

**Provider type change in `auth_controller.dart`:**

```dart
// Antes
class AuthController extends Notifier<AsyncValue<User?>> {
  @override
  AsyncValue<User?> build() {
    // ...
    Future.microtask(_restore);
    return const AsyncValue.loading();
  }
}

// Depois
class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    // ... (lógica do _restore inline, retorna User? em vez de AsyncValue<User?>)
  }
}
```

- [ ] **Step 1: Rewrite `AuthController` class declaration and `build()`**

```dart
class AuthController extends AsyncNotifier<User?> {
  late final IAuthRepository _repository;
  late final AuthLocalStorage _storage;
  late final SessionCacheNotifier _sessionCache;

  @override
  Future<User?> build() async {
    _repository = ref.read(authRepositoryProvider);
    _storage = ref.read(authLocalStorageProvider);
    _sessionCache = ref.read(sessionCacheProvider.notifier);

    await _sessionCache.restore();
    final accessToken = await _storage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return null;

    final user = await _storage.getUser();
    if (user == null) {
      await _storage.clear();
      _sessionCache.clear();
      return null;
    }

    await _registerFcmToken();
    return user;
  }
}
```

- [ ] **Step 2: Update `login()` and `register()` — remove `const AsyncValue.loading()` assignments, keep `AsyncValue.data()` / `AsyncValue.error()`**

```dart
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.login(email: email, password: password);
      await _sessionCache.hydrate({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      state = AsyncValue.data(result.user);
      await _registerFcmToken();
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<AuthResult> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await _repository.register(
        email: email,
        password: password,
        name: name,
      );
      await _sessionCache.hydrate({
        'settings': result.session.settings,
        'soul': result.session.soul,
        'contexts': result.session.contexts,
        'routines': result.session.routines,
      });
      state = AsyncValue.data(result.user);
      await _registerFcmToken();
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
```

- [ ] **Step 3: Remove `_restore()` method** (logic moved inline into `build()`)

Delete the entire `_restore()` method (lines 28-44).

- [ ] **Step 4: Update `_clearSession()`, `logout()`, `onSessionExpired()` to use `AsyncValue.data(null)`**

```dart
  Future<void> _clearSession() async {
    await _storage.clear();
    _sessionCache.clear();
    state = const AsyncValue.data(null);
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repository.logout();
    } catch (e) {
      debugPrint('logout error: $e');
    }
    await ref.read(lastRouteStoreProvider).clear();
    await _clearSession();
  }

  Future<void> onSessionExpired() async {
    await _clearSession();
  }
```

O método `login()` e `register()` continuam settando `state = const AsyncValue.loading()`, `AsyncValue.data()`, `AsyncValue.error()` — o `AsyncNotifier` expõe `state` como `AsyncValue<T>`, e esses assignments funcionam igual.

- [ ] **Step 5: Update provider declaration in `lib/core/di/providers.dart`**

```dart
// Antes
final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<User?>>(AuthController.new);

// Depois
final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
```

- [ ] **Step 6: Update tests in `test/features/auth/domain/auth_state_test.dart`**

Trocas necessárias:

```dart
// Antes
final user = container.read(authControllerProvider).requireValue;
// Depois
final user = container.read(authControllerProvider).requireValue;
```
(Não muda — `AsyncNotifierProvider` também expõe `.requireValue`, `.value`, `.when()`, etc.)

```dart
// Antes
container.read(authControllerProvider).hasError
// Depois
container.read(authControllerProvider).hasError
```
(Não muda — `AsyncValue` continua exposto.)

Nenhuma mudança significativa nos testes — `AsyncNotifierProvider` expõe a mesma interface `AsyncValue<T>`.

- [ ] **Step 7: Run `dart analyze lib/core/di/providers.dart lib/features/auth/presentation/controllers/auth_controller.dart` and fix any type errors**

Run: `dart analyze lib/core/di/providers.dart lib/features/auth/presentation/controllers/auth_controller.dart`
Expected: No errors.

---

### Task 2: Fix all `authControllerProvider` consumers — `.asData?.value` → `.when()` ou `.select()`

**Files:**
- Modify: `lib/core/auth/current_user.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Fix `current_user.dart`**

```dart
// Antes
final currentUserIdProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(authControllerProvider).asData?.value?.id;
});

// Depois
final currentUserIdProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(authControllerProvider).valueOrNull?.id;
});
```

- [ ] **Step 2: Verify `lib/core/router/app_router.dart`**

Linha 31: `ref.read(authControllerProvider)` retorna `AsyncValue<User?>` — não muda com `AsyncNotifierProvider`.
Linha 34: `ref.listen<AsyncValue<User?>>(authControllerProvider, ...)` — não muda.
O `ValueNotifier<AsyncValue<User?>>` e o `authGuardRedirect(authState: notifier.value)` continuam funcionando. **Nenhuma alteração necessária.**

- [ ] **Step 3: Verify `lib/main.dart`**

Linha 75: `ref.listen<AsyncValue<User?>>(authControllerProvider, ...)` — o tipo continua sendo `AsyncValue<User?>`, não precisa mudar.

---

### Task 3: Fix login/register screens — `.isLoading` → padrão sem guard + `.when()`

**Files:**
- Modify: `lib/features/auth/presentation/login_screen.dart`
- Modify: `lib/features/auth/presentation/register_screen.dart`

- [ ] **Step 1: Fix `login_screen.dart` — remover `.isLoading`**

```dart
// Antes (linha 42)
Future<void> _submit() async {
  if (ref.read(authControllerProvider).isLoading) return;

// Depois
Future<void> _submit() async {
  // Não precisa do guard — o AppButton já desabilita via isLoading
```

```dart
// Antes (linhas 61-63)
final isLoading = ref.watch(
  authControllerProvider.select((s) => s.isLoading),
);

// Depois — usa .when() no lugar
final isLoading = ref.watch(authControllerProvider).isLoading;
```
(Mantém `isLoading` do `AsyncValue` — agora que `authControllerProvider` é `AsyncNotifierProvider`, ainda expõe `.isLoading`.)

Na verdade, como o `AsyncValue.when()` é o padrão correto. Mas o `isLoading` é usado só pra passar pro `AppButton`. Pode manter:

```dart
final isLoading = ref.watch(authControllerProvider).isLoading;
```

O `AppButton(isLoading: isLoading)` funciona. O `_submit()` não precisa mais do guard porque o botão já desabilita.

- [ ] **Step 2: Fix `register_screen.dart` — mesma alteração da login_screen**

```dart
// Antes (linha 45)
if (ref.read(authControllerProvider).isLoading) return;
// Depois: remover a linha

// Antes (linhas 65-67)
final isLoading = ref.watch(
  authControllerProvider.select((s) => s.isLoading),
);
// Depois
final isLoading = ref.watch(authControllerProvider).isLoading;
```

- [ ] **Step 3: Run `dart analyze` on both files**

Run: `dart analyze lib/features/auth/presentation/login_screen.dart lib/features/auth/presentation/register_screen.dart`
Expected: No errors.

---

### Task 4: Fix `settings_screen.dart` — `.asData?.value` → `.when()` + reactividade

**File:** `lib/features/settings/presentation/settings_screen.dart`

- [ ] **Step 1: Trocar accesso a `authControllerProvider`**

```dart
// Antes (linha 28)
final account = ref.watch(authControllerProvider).asData?.value;

// Depois
final account = ref.watch(authControllerProvider).valueOrNull;
```

- [ ] **Step 2: Trocar `ref.read(syncStateProvider)` por `ref.watch` (linha 119)**

```dart
// Antes
final sync = ref.read(syncStateProvider);
// Depois
final sync = ref.watch(syncStateProvider);
```

---

### Task 5: Migrate `ChatController` — `Notifier<AsyncValue<ChatState>>` → `AsyncNotifier<ChatState>`

**Files:**
- Modify: `lib/features/agent/presentation/controllers/chat_controller.dart`
- Modify: `test/features/agent/presentation/controllers/chat_controller_test.dart`

- [ ] **Step 1: Change class declaration and provider**

```dart
// Antes
final chatControllerProvider =
    NotifierProvider<ChatController, AsyncValue<ChatState>>(ChatController.new);

class ChatController extends Notifier<AsyncValue<ChatState>> {
  @override
  AsyncValue<ChatState> build() {
    // ...
    Future.microtask(() => _loadHistory(sessionId));
    return const AsyncValue.loading();
  }

// Depois
final chatControllerProvider =
    AsyncNotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends AsyncNotifier<ChatState> {
  @override
  Future<ChatState> build() async {
    final sessionId = ref.watch(sessionManagerProvider);
    ref.onDispose(() => _sseSub?.cancel());
    try {
      final messages = await ref
          .read(chatRepositoryProvider)
          .getHistory(sessionId);
      return chatState(messages: messages);
    } on ApiException catch (e, st) {
      throw e.message;
    } catch (e, st) {
      rethrow;
    }
  }
```

- [ ] **Step 2: Update all `state = AsyncValue.data(...)` assignments to `state = AsyncValue.data(...)`**

O `AsyncNotifier` expõe `state` como `AsyncValue<T>`. Assignments como `state = AsyncValue.data(chatState(...))` continuam funcionando. Assignments manuais de `state = const AsyncValue.loading()` também funcionam. O único lugar que muda é o acesso ao valor atual:

```dart
// Antes: state.value?.messages
// Depois: state.value?.messages (não muda — AsyncNotifier.state é AsyncValue<T>)
```

Não precisa mudar nada no corpo do `ChatController` além da declaração e do `build()`.

- [ ] **Step 3: Remove `_loadHistory()` method** (lógica movida inline para `build()`)

Delete the `_loadHistory()` method (lines 69-81).

- [ ] **Step 4: Run `dart analyze`**

Run: `dart analyze lib/features/agent/presentation/controllers/chat_controller.dart`
Expected: No errors.

---

### Task 6: Fix `chat_screen.dart` — `.isLoading`/`.hasError` → `whenOrNull`

**File:** `lib/features/agent/presentation/chat_screen.dart`

- [ ] **Step 1: Substituir `ref.listen`**

```dart
// Antes (linhas 19-23)
ref.listen<AsyncValue<ChatState>>(chatControllerProvider, (prev, next) {
  if (!next.isLoading && next.hasError && next.error != prev?.error) {
    AppMessenger.showError(next.error.toString());
  }
});

// Depois
ref.listen<AsyncValue<ChatState>>(chatControllerProvider, (prev, next) {
  next.whenOrNull(error: (err, _) {
    if (err.toString() != prev?.error?.toString()) {
      AppMessenger.showError(err.toString());
    }
  });
});
```

- [ ] **Step 2: Run `dart analyze`**

Run: `dart analyze lib/features/agent/presentation/chat_screen.dart`
Expected: No errors.

---

### Task 7: Migrate `ShareNoteController` — `Notifier<AsyncValue<void>>` → `AsyncNotifier<void>`

**Files:**
- Modify: `lib/features/notes/presentation/controllers/share_note_controller.dart`

- [ ] **Step 1: Change class and provider declaration**

```dart
// Antes
final shareNoteControllerProvider =
    NotifierProvider.autoDispose<ShareNoteController, AsyncValue<void>>(
  ShareNoteController.new,
);

class ShareNoteController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

// Depois
final shareNoteControllerProvider =
    AsyncNotifierProvider.autoDispose<ShareNoteController, void>(
  ShareNoteController.new,
);

class ShareNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}
```

O corpo do `share()` não muda — `AsyncValue.guard()` e `state = const AsyncValue.loading()` funcionam igual.

- [ ] **Step 2: Run `dart analyze`**

---

### Task 8: Fix `share_note_sheet.dart` — `.isLoading`/`.hasError` → `.when()`

**File:** `lib/features/notes/presentation/widgets/share_note_sheet.dart`

- [ ] **Step 1: Substituir `shareState.isLoading` por `.when()`**

```dart
  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareNoteControllerProvider);

    // Antes: usos de shareState.isLoading e shareState.hasError
    // Depois: envolve o build com shareState.when() ou usa .isLoading para os enabled

    return shareState.when(
      data: (_) => _buildForm(context),
      loading: () => _buildForm(context, isLoading: true),
      error: (err, _) => _buildForm(context, error: err),
    );
  }
```

Mas isso mudaria muito a estrutura. Alternativa mais prática: manter `.isLoading` para desabilitar campos, mas substituir o bloco `if (shareState.hasError)` por `shareState.whenOrNull(error: ...)`.

Solução minimal:

```dart
// Antes: TextField(enabled: !shareState.isLoading, ...)
// Mantém — .isLoading no AsyncNotifierProvider funciona

// Antes (linhas 101-111)
if (shareState.hasError) ...[
  // ...
]

// Depois
shareState.whenOrNull(error: (err, _) => Padding(
  padding: const EdgeInsets.only(top: AppSpacing.sm),
  child: Text(
    err is ApiException ? err.message : err.toString(),
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.error,
    ),
  ),
)),
```

---

### Task 9: Fix `soul_editor_screen.dart` — remover `_initialized` + `.asData?.value`

**File:** `lib/features/settings/presentation/soul_editor_screen.dart`

- [ ] **Step 1: Remover `bool _initialized = false` e usar `ref.listen` para popular o controller**

```dart
// Antes (linha 26)
bool _initialized = false;

// Depois: remover a linha

// Adicionar no build(), antes do return:
ref.listen(soulProvider, (prev, next) {
  next.whenOrNull(data: (soul) {
    if (_controller.text.isEmpty) {
      _controller.text = soul.personality;
    }
  });
});
```

- [ ] **Step 2: Substituir `.asData?.value` por `soulAsync.when()`**

```dart
// Antes (linhas 68-75)
final soulAsync = ref.watch(soulProvider);
final saveState = ref.watch(soulSaveProvider);
final soul = soulAsync.asData?.value;

if (!_initialized && soul != null) {
  _initialized = true;
  _controller.text = soul.personality;
}

// Depois — remover as linhas 68-75, manter só o ref.watch dentro do .when() no body
// O listener do step 1 substitui a inicialização
// O saveState ainda precisa ser assistido

final saveState = ref.watch(soulSaveProvider);

return Scaffold(
  bottomNavigationBar: SoulFooter(
    isSaving: saveState.isLoading,
    onSave: _save,
    onRestore: _restoreDefault,
  ),
  body: CustomScrollView(
    slivers: [
      const AdaptiveSliverNavBar(title: Text(SettingsStrings.title)),
      ref.watch(soulProvider).when(
        loading: () => const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => SliverFillRemaining(
          child: AppErrorView(
            title: err is ApiException ? err.message : err.toString(),
            onRetry: () => ref.invalidate(soulProvider),
          ),
        ),
        data: (_) => SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverFillRemaining(
            hasScrollBody: true,
            child: SoulForm(controller: _controller),
          ),
        ),
      ),
    ],
  ),
);
```

---

### Task 10: Migrate `soulProvider` — `FutureProvider` → `AsyncNotifier`

**Files:**
- Modify: `lib/features/settings/presentation/controllers/soul_editor_controller.dart`

- [ ] **Step 1: Transform `soulProvider` em `AsyncNotifierProvider`**

```dart
// Antes
final soulProvider = FutureProvider.autoDispose<Soul>((ref) async {
  final cache = ref.read(sessionCacheProvider);
  if (cache.soul.isNotEmpty) {
    return Soul(personality: cache.soul['personality'] as String? ?? '');
  }
  return ref.read(settingsRepositoryProvider).getSoul();
});

// Depois
final soulProvider =
    AsyncNotifierProvider.autoDispose<SoulNotifier, Soul>(SoulNotifier.new);

class SoulNotifier extends AsyncNotifier<Soul> {
  @override
  Future<Soul> build() async {
    final cache = ref.read(sessionCacheProvider);
    if (cache.soul.isNotEmpty) {
      return Soul(personality: cache.soul['personality'] as String? ?? '');
    }
    return ref.read(settingsRepositoryProvider).getSoul();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}
```

- [ ] **Step 2: Atualizar `soulSaveProvider` para invalidar corretamente**

```dart
// No SoulSaveNotifier.save():
// Antes
ref.invalidate(soulProvider);
// Depois
ref.invalidate(soulProvider);
```
(Não muda — `ref.invalidate()` funciona com `AsyncNotifierProvider`.)

---

### Task 11: Fix `note_editor_screen.dart` — `.asData?.value` → `.when()`

**File:** `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Substituir `tasksAsync.asData?.value`**

```dart
// Antes (linhas 66-69)
final tasksAsync = ref.watch(tasksByNoteStreamProvider(widget.noteId));
final tasksMap = tasksAsync.asData?.value != null
    ? {for (final t in tasksAsync.asData!.value) t.id: t}
    : const <String, TaskModel>{};

// Depois
final tasksAsync = ref.watch(tasksByNoteStreamProvider(widget.noteId));
final tasksMap = tasksAsync.when(
  data: (tasks) => {for (final t in tasks) t.id: t},
  loading: () => const <String, TaskModel>{},
  error: (_, __) => const <String, TaskModel>{},
);
```

---

### Task 12: Fix `inbox_screen.dart` — `.asData?.value` → `.when()`

**File:** `lib/features/notes/presentation/inbox_screen.dart`

- [ ] **Step 1: Mesma substituição da note_editor_screen**

```dart
// Antes (linhas 85-87)
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

---

### Task 13: Fix `telegram_link_screen.dart` — remover `_waitingForLink`

**File:** `lib/features/telegram/presentation/telegram_link_screen.dart`

- [ ] **Step 1: Adicionar `isPairing` ao `TelegramPairingState`**

Em `lib/features/telegram/presentation/controllers/telegram_link_controller.dart`:

```dart
class TelegramPairingState {
  final bool isPairing;
  final String? code;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final String? errorMessage;

  const TelegramPairingState({
    this.isPairing = false,
    this.code,
    this.expiresAt,
    this.createdAt,
    this.errorMessage,
  });

  TelegramPairingState copyWith({
    bool? isPairing,
    String? code,
    DateTime? expiresAt,
    DateTime? createdAt,
    String? errorMessage,
  }) {
    return TelegramPairingState(
      isPairing: isPairing ?? this.isPairing,
      code: code ?? this.code,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      errorMessage: errorMessage,
    );
  }

  // ... existing code
}
```

E no `TelegramPairingController.start()`:

```dart
  Future<void> start() async {
    state = state.copyWith(isPairing: true, errorMessage: null);
    try {
      final result = await ref.read(telegramRepositoryProvider).generateLink();
      state = state.copyWith(
        code: result.code,
        expiresAt: result.expiresAt,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isPairing: false,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }
```

Atualizar também os métodos que finalizam o pairing para setar `isPairing: false`.

- [ ] **Step 2: Remover `_waitingForLink` e usar `telegramPairingProvider`**

No `telegram_link_screen.dart`:

```dart
// Antes (linha 24)
bool _waitingForLink = false;

// Depois: remover a linha
```

```dart
// Antes (linha 31)
if (!prevLinked && nextLinked && _waitingForLink && mounted) {

// Depois
final pairingState = ref.read(telegramPairingProvider);
if (!prevLinked && nextLinked && pairingState.isPairing && mounted) {
```

```dart
// Antes (linha 78)
if (mounted) setState(() => _waitingForLink = true);

// Depois: o start() já seta isPairing = true no provider
// Apenas chamar start() sem setState
```

---

### Task 14: Fix `mcp_screen.dart` — `_isGenerating` → `McpTokenController`

**File:**
- Create: `lib/features/settings/presentation/controllers/mcp_token_controller.dart`
- Modify: `lib/features/settings/presentation/mcp_screen.dart`

- [ ] **Step 1: Criar `McpTokenController`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';

final mcpTokenProvider =
    AsyncNotifierProvider.autoDispose<McpTokenController, String?>(
  McpTokenController.new,
);

class McpTokenController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<void> generate() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(settingsRepositoryProvider).generateMcpToken(),
    );
  }
}
```

- [ ] **Step 2: Atualizar `mcp_screen.dart` — remover `_isGenerating`, `_generatedToken`, usar provider**

```dart
// Antes
class _McpScreenState extends ConsumerState<McpScreen> {
  String? _generatedToken;
  bool _isGenerating = false;

  Future<void> _generateToken() async {
    setState(() => _isGenerating = true);
    try {
      final token = await ref.read(settingsRepositoryProvider).generateMcpToken();
      if (!mounted) return;
      setState(() {
        _generatedToken = token;
        _isGenerating = false;
      });
      AppMessenger.showSuccess('Token gerado com sucesso.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      AppMessenger.showError(e.message);
    }
  }

// Depois
class _McpScreenState extends ConsumerState<McpScreen> {
  Future<void> _generateToken() async {
    await ref.read(mcpTokenProvider.notifier).generate();
    if (!mounted) return;
    final state = ref.read(mcpTokenProvider);
    state.whenOrNull(
      data: (_) => AppMessenger.showSuccess('Token gerado com sucesso.'),
      error: (err, _) => AppMessenger.showError(
        err is ApiException ? err.message : err.toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokenAsync = ref.watch(mcpTokenProvider);
    // ...
  }
```

Atualizar `_TokenCard` para receber `AsyncValue<String?>` em vez de `String?` + `bool`:

```dart
// Antes
_TokenCard(
  generatedToken: _generatedToken,
  isGenerating: _isGenerating,
  onGenerate: _generateToken,
),

// Depois
_TokenCard(
  tokenAsync: tokenAsync,
  onGenerate: _generateToken,
),
```

```dart
class _TokenCard extends StatelessWidget {
  const _TokenCard({
    required this.tokenAsync,
    required this.onGenerate,
  });

  final AsyncValue<String?> tokenAsync;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return tokenAsync.when(
      data: (token) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ... mesmo conteúdo
              if (token != null) ...[
                // mostrar token
              ] else ...[
                AppButton(
                  text: 'Gerar Token',
                  onPressed: onGenerate,
                ),
              ],
            ],
          ),
        ),
      ),
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (err, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text('Erro: $err'),
        ),
      ),
    );
  }
}
```

---

### Task 15: Fix `memories_screen.dart` — `.hasError` → `whenOrNull` no listen

**File:** `lib/features/memories/presentation/memories_screen.dart`

- [ ] **Step 1: Substituir `next.hasError` por `whenOrNull`**

```dart
// Antes (linha 23)
if (next.hasError && (prev == null || !prev.hasError)) {
  AppMessenger.showError(next.error.toString());
}

// Depois
next.whenOrNull(error: (err, _) {
  if (prev == null || prev.hasError == false) {
    AppMessenger.showError(err.toString());
  }
});
```

---

### Task 16: Logout invalida dependentes

**File:** `lib/features/auth/presentation/controllers/auth_controller.dart`

- [ ] **Step 1: Adicionar `ref.invalidate(...)` no `logout()`**

```dart
  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      await _repository.logout();
    } catch (e) {
      debugPrint('logout error: $e');
    }
    await ref.read(lastRouteStoreProvider).clear();
    await _clearSession();

    // Invalidar providers dependentes
    ref.invalidate(soulProvider);
    ref.invalidate(contextsProvider);
    ref.invalidate(routinesProvider);
    ref.invalidate(briefHistoryProvider);
    ref.invalidate(chatControllerProvider);
    ref.invalidate(syncServiceProvider);
    ref.invalidate(telegramStatusProvider);
    ref.invalidate(memoriesControllerProvider);
  }
```

---

### Task 17: Adicionar `select()` para performance

**File:** `lib/features/settings/presentation/settings_screen.dart` (já feito no Task 4)
**File:** `lib/features/notes/presentation/widgets/share_note_sheet.dart`

- [ ] **Step 1: No `share_note_sheet.dart`, manter `.isLoading` (já é select implícito do `AsyncValue`)**

O `AsyncNotifierProvider` expõe `.isLoading` sem precisar de provider inteiro. O watch já é otimizado.

---

### Task 18: Update test stubs that extend migrated controllers

**Files:**
- Modify: `test/features/agent/presentation/chat_screen_test.dart`
- Modify: `test/features/settings/presentation/settings_screen_test.dart`

- [ ] **Step 1: Fix `_TestChatController` — `build()` return type**

```dart
// Antes
class _TestChatController extends ChatController {
  _TestChatController(this.initialState);
  final ChatState initialState;

  @override
  AsyncValue<ChatState> build() => AsyncValue.data(initialState);

// Depois
class _TestChatController extends ChatController {
  _TestChatController(this.initialState);
  final ChatState initialState;

  @override
  Future<ChatState> build() async => initialState;
```

- [ ] **Step 2: Fix `_TestAuthController` — `build()` return type**

```dart
// Antes
class _TestAuthController extends AuthController {
  _TestAuthController(this._user);
  final User? _user;

  @override
  AsyncValue<User?> build() => AsyncValue.data(_user);

// Depois
class _TestAuthController extends AuthController {
  _TestAuthController(this._user);
  final User? _user;

  @override
  Future<User?> build() async => _user;
```

---

### Verification

- [ ] **Step 1: Run full static analysis**

Run: `dart analyze lib/`
Expected: No errors (or only pre-existing warnings).

- [ ] **Step 2: Run tests**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor(riverpod): migrate to AsyncNotifier, fix state patterns, add logout invalidation"
```
