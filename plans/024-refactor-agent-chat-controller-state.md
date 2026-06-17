# Plan 024: Refactor Agent Chat Controller State

> **Executor instructions**: Follow this plan step by step. Run every verification command before moving on. If a STOP condition occurs, stop and report; do not improvise.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- lib/features/agent/presentation/controllers/chat_controller.dart lib/features/agent/data/chat_sse.dart lib/features/agent/domain/sse_chat_event.dart test/features/agent`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/023-normalize-agent-chat-stream-contract.md`
- **Category**: tech-debt
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

`ChatController` currently mixes persisted messages, optimistic UI, SSE parsing, tool activity text, and error handling in one method. It also suppresses a Riverpod lint with `// ignore_for_file: invalid_use_of_internal_member`. After Plan 023 normalizes stream events, the controller should represent chat state explicitly so UI work can consume real state instead of markdown status embedded in assistant content.

## Current state

- `lib/features/agent/presentation/controllers/chat_controller.dart:15-18` defines `ChatState` with only `messages` and `isStreaming`.
- `lib/features/agent/presentation/controllers/chat_controller.dart:99-114` turns tool events into `*(Pensando...)*` text inside assistant content.
- `lib/features/agent/presentation/controllers/chat_controller.dart:135-144` reports errors through `AsyncError.copyWithPrevious`, leaving recovery state implicit.
- `lib/features/agent/data/chat_sse.dart` owns the stream transport. After Plan 023 it should expose normalized events with compatibility getters.

Repo conventions:

- Manual Riverpod providers only. No codegen.
- User text input stays in widgets; shared async chat state can remain a `Notifier<AsyncValue<ChatState>>`.
- Model new controller tests after existing provider override tests in `test/features/agent/presentation/chat_screen_test.dart`.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Controller tests | `flutter test test/features/agent/presentation/controllers/chat_controller_test.dart` | all pass |
| Agent tests | `flutter test test/features/agent` | all pass |
| Analyze | `dart analyze lib/features/agent test/features/agent` | no issues found |

## Scope

**In scope**:

- `lib/features/agent/presentation/controllers/chat_controller.dart`
- `lib/features/agent/data/chat_sse.dart` only to add `chatSSEProvider` if Plan 023 did not already add it
- `test/features/agent/presentation/controllers/chat_controller_test.dart` (create)

**Out of scope**:

- `AgentChatView` UI layout
- Backend event emission
- Tool confirmation UX
- Prompt/context changes
- Any note editor/card files

## Steps

### Step 1: Add injectable SSE provider

If Plan 023 did not add it, add this to `lib/features/agent/data/chat_sse.dart`:

```dart
final chatSSEProvider = Provider.autoDispose<ChatSSE>((ref) {
  return ChatSSE(apiClient: ref.watch(apiClientProvider));
});
```

Imports required:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
```

**Verify**:

```powershell
dart analyze lib/features/agent/data/chat_sse.dart
```

Expected: no issues.

### Step 2: Expand `ChatState`

In `chat_controller.dart`, replace the typedef with:

```dart
typedef ChatState = ({
  List<MessageModel> messages,
  bool isStreaming,
  String? activeToolLabel,
  String? errorMessage,
  String? retryMessage,
});
```

Add a helper:

```dart
ChatState chatState({
  List<MessageModel> messages = const [],
  bool isStreaming = false,
  String? activeToolLabel,
  String? errorMessage,
  String? retryMessage,
}) {
  return (
    messages: messages,
    isStreaming: isStreaming,
    activeToolLabel: activeToolLabel,
    errorMessage: errorMessage,
    retryMessage: retryMessage,
  );
}
```

Update `_loadHistory` to use:

```dart
state = AsyncValue.data(chatState(messages: messages));
```

**Verify**:

```powershell
dart analyze lib/features/agent/presentation/controllers/chat_controller.dart
```

Expected: existing call sites may fail until later steps; do not proceed if errors are unrelated to `ChatState` shape.

### Step 3: Rewrite stream event handling

In `sendMessage`, replace `ChatSSE(apiClient: ref.read(apiClientProvider))` with:

```dart
final sse = ref.read(chatSSEProvider);
```

Replace branches comparing raw legacy strings with normalized getters:

```dart
if (event.isContentDelta && event.delta != null) {
  buffer.write(event.delta);
  state = AsyncValue.data(chatState(
    messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
    isStreaming: true,
    retryMessage: trimmed,
  ));
} else if (event.isToolStarted) {
  state = AsyncValue.data(chatState(
    messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
    isStreaming: true,
    activeToolLabel: event.toolLabel ?? 'Executando acao',
    retryMessage: trimmed,
  ));
} else if (event.isToolFinished || event.isToolFailed || event.isToolResult) {
  state = AsyncValue.data(chatState(
    messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
    isStreaming: true,
    retryMessage: trimmed,
  ));
} else if (event.isDone) {
  final content = event.finalContent ?? buffer.toString();
  state = AsyncValue.data(chatState(
    messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: content)],
    isStreaming: false,
    retryMessage: trimmed,
  ));
}
```

Remove `dart:convert`, `currentToolStatus`, and any code that writes thinking/status strings into `MessageModel.content`.

**Verify**:

```powershell
dart analyze lib/features/agent/presentation/controllers/chat_controller.dart
```

Expected: no issues except missing helper methods added in next step.

### Step 4: Add recovery helpers

Add:

```dart
void _setRecoverableError(String message, String retryMessage) {
  final current = state.valueOrNull;
  if (current == null) {
    state = AsyncValue.error(message, StackTrace.current);
    return;
  }
  state = AsyncValue.data(chatState(
    messages: current.messages,
    isStreaming: false,
    errorMessage: message,
    retryMessage: retryMessage,
  ));
}

Future<void> retryLastMessage() async {
  final retry = state.valueOrNull?.retryMessage;
  if (retry == null || retry.trim().isEmpty) return;
  await sendMessage(retry);
}

Future<void> cancelStreaming() async {
  await _sseSub?.cancel();
  _sseSub = null;
  final current = state.valueOrNull;
  if (current == null) return;
  state = AsyncValue.data(chatState(
    messages: current.messages,
    isStreaming: false,
    retryMessage: current.retryMessage,
  ));
}
```

Use `_setRecoverableError(...)` from stream `onError` and normalized error events. Remove the file-level Riverpod ignore.

**Verify**:

```powershell
dart analyze lib/features/agent/presentation/controllers/chat_controller.dart
```

Expected: no issues.

### Step 5: Add controller tests

Create `test/features/agent/presentation/controllers/chat_controller_test.dart` covering:

- history load returns `chatState(messages: history)`
- `tool_started` sets `activeToolLabel`
- `content_delta` updates assistant content without status text
- `message_finished` clears `isStreaming`
- stream error keeps partial messages and sets `errorMessage`
- `cancelStreaming()` clears `isStreaming`

Use fake `IChatRepository` and override `chatSSEProvider`.

**Verify**:

```powershell
flutter test test/features/agent/presentation/controllers/chat_controller_test.dart
```

Expected: all tests pass.

### Step 6: Final verification

Run:

```powershell
flutter test test/features/agent
dart analyze lib/features/agent test/features/agent
```

Expected: all tests pass and analyzer has no issues.

## Done criteria

- [ ] No `invalid_use_of_internal_member` ignore remains.
- [ ] No tool status text is appended to assistant message content.
- [ ] `ChatState` exposes active tool, retry, and error state.
- [ ] Controller tests cover success, tool activity, error, retry, and cancel.
- [ ] Focused Flutter tests and analysis pass.

## STOP conditions

- Plan 023 has not landed or `SSEChatEvent` lacks normalized compatibility getters.
- `ChatController` must change public UI widgets to compile.
- Tests require live backend/network.
- Changes require touching backend code or note editor files.

## Maintenance notes

This plan prepares state for UI rendering but intentionally does not design the visual treatment. Plan 025 should consume `activeToolLabel`, `errorMessage`, `retryMessage`, and `cancelStreaming()` from this controller.
