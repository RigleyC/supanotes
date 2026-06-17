# Plan 025: Render Agent Chat Recovery UX

> **Executor instructions**: Follow this plan step by step. Run every verification command before moving on. If a STOP condition occurs, stop and report; do not improvise.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- lib/features/agent/presentation/widgets/agent_chat_view.dart lib/features/agent/presentation/chat_screen.dart test/features/agent/presentation`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/024-refactor-agent-chat-controller-state.md`
- **Category**: direction
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

After the controller exposes explicit stream state, the chat UI should stop hiding important activity. Users need to know when the agent is searching, when it failed, and how to retry or cancel without reading internal tool names or JSON. This plan renders the state from Plan 024 without changing backend behavior.

## Current state

- `AgentChatView` accepts only `messages`, `loaded`, `streaming`, and `onSend`.
- Empty state is a static `EmptyState`.
- `ChatScreen` shows errors through a snackbar instead of inline recovery.
- Existing tests live in `test/features/agent/presentation/widgets/agent_chat_view_test.dart` and `chat_screen_test.dart`.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Widget tests | `flutter test test/features/agent/presentation/widgets/agent_chat_view_test.dart` | all pass |
| Presentation tests | `flutter test test/features/agent/presentation` | all pass |
| Analyze | `dart analyze lib/features/agent/presentation test/features/agent/presentation` | no issues found |

## Scope

**In scope**:

- `lib/features/agent/presentation/widgets/agent_chat_view.dart`
- `lib/features/agent/presentation/chat_screen.dart`
- `test/features/agent/presentation/widgets/agent_chat_view_test.dart`
- `test/features/agent/presentation/chat_screen_test.dart`

**Out of scope**:

- Backend events
- Controller state shape
- Tool confirmation flows
- Replacing `flutter_chat_ui`

## Steps

### Step 1: Extend `AgentChatView` API

Add constructor fields:

```dart
final String? activeToolLabel;
final String? errorMessage;
final VoidCallback? onRetry;
final VoidCallback? onCancel;
```

Constructor parameters:

```dart
required this.activeToolLabel,
required this.errorMessage,
this.onRetry,
this.onCancel,
```

Update all existing tests to pass `null` for the new optional state.

**Verify**:

```powershell
dart analyze lib/features/agent/presentation/widgets/agent_chat_view.dart test/features/agent/presentation/widgets/agent_chat_view_test.dart
```

Expected: no issues.

### Step 2: Add status bar widget

In `agent_chat_view.dart`, add a private `_AgentChatStatusBar` below the chat area. It should:

- show `activeToolLabel` with a small progress indicator
- show `errorMessage` with an error icon
- show `Tentar novamente` when `onRetry` is non-null
- show an icon button with tooltip `Cancelar resposta` when `onCancel` is non-null

Keep the visual compact: one row, surface background, 16px horizontal padding.

**Verify**:

```powershell
flutter test test/features/agent/presentation/widgets/agent_chat_view_test.dart
```

Expected: existing tests still pass after constructor updates.

### Step 3: Add widget tests for status states

Add tests:

```dart
testWidgets('shows tool activity while streaming', (tester) async {
  await tester.pumpWidget(wrap(AgentChatView(
    messages: const [],
    loaded: true,
    streaming: true,
    activeToolLabel: 'Buscando notas',
    errorMessage: null,
    onRetry: null,
    onCancel: () {},
    onSend: (_) {},
  )));

  expect(find.text('Buscando notas'), findsOneWidget);
  expect(find.byTooltip('Cancelar resposta'), findsOneWidget);
});

testWidgets('shows inline error with retry action', (tester) async {
  var retried = false;
  await tester.pumpWidget(wrap(AgentChatView(
    messages: const [],
    loaded: true,
    streaming: false,
    activeToolLabel: null,
    errorMessage: 'Falha no stream',
    onRetry: () => retried = true,
    onCancel: null,
    onSend: (_) {},
  )));

  expect(find.text('Falha no stream'), findsOneWidget);
  await tester.tap(find.text('Tentar novamente'));
  expect(retried, isTrue);
});
```

**Verify**:

```powershell
flutter test test/features/agent/presentation/widgets/agent_chat_view_test.dart
```

Expected: all tests pass.

### Step 4: Add prompt suggestions to empty state

Replace the static empty builder with a small empty-state component that keeps the existing title/subtitle and adds three `ActionChip`s:

- `Resuma minhas notas recentes`
- `Quais tarefas vencem hoje?`
- `Organize meu inbox`

Each chip calls `onSend(prompt)`.

**Verify**:

```powershell
flutter test test/features/agent/presentation/widgets/agent_chat_view_test.dart
```

Expected: tests pass. Add a test that tapping one chip sends that exact prompt.

### Step 5: Wire `ChatScreen`

Update `ChatScreen` to pass:

```dart
activeToolLabel: state?.activeToolLabel,
errorMessage: state?.errorMessage,
onRetry: state?.retryMessage == null
    ? null
    : () => ref.read(chatControllerProvider.notifier).retryLastMessage(),
onCancel: isStreaming
    ? () => ref.read(chatControllerProvider.notifier).cancelStreaming()
    : null,
```

Keep snackbar error handling only for load-level `AsyncError`. Stream recovery errors should render inline through `errorMessage`.

**Verify**:

```powershell
flutter test test/features/agent/presentation/chat_screen_test.dart
```

Expected: pass.

### Step 6: Final verification

Run:

```powershell
flutter test test/features/agent/presentation
dart analyze lib/features/agent/presentation test/features/agent/presentation
```

Expected: all pass, no analyzer issues.

## Done criteria

- [ ] Tool activity renders as human label.
- [ ] Inline error and retry render.
- [ ] Cancel action renders while streaming.
- [ ] Empty state has useful prompt suggestions.
- [ ] Presentation tests and analyzer pass.

## STOP conditions

- Plan 024 has not landed.
- `ChatState` does not expose `activeToolLabel`, `errorMessage`, or `retryMessage`.
- UI changes require replacing `flutter_chat_ui`.
- Any change requires backend edits.

## Maintenance notes

This plan deliberately keeps UX compact. Confirmation/preview UI for sensitive tools belongs in Plan 026.
