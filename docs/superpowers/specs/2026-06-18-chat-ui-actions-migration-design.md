# Chat UI Actions Migration Design

## Context

SupaNotes currently renders the agent chat with `flutter_chat_core` and
`flutter_chat_ui`. The app owns the agent state in `ChatController`, streams
assistant output from `POST /api/v1/agent/chat/stream`, and reduces tool events
to simple UI strings such as `activeToolLabel` and `errorMessage`.

The new target package is `flutter_gen_ai_chat_ui` version `^2.14.0`. The
migration should use the package as the primary chat surface, including its
native input, streaming/markdown rendering, stop generation behavior, and rich
AI action-style UI for backend tool events.

Sensitive tools already produce `confirmation_required` events, but the backend
currently stops the loop after emitting that event and does not expose a
confirmed execution contract. This design adds persisted pending confirmations
so the user can explicitly approve or cancel sensitive actions.

## Goals

- Replace `flutter_chat_core` and `flutter_chat_ui` with
  `flutter_gen_ai_chat_ui`.
- Use `AiChatWidget` as the chat surface, including its native composer.
- Preserve user-facing behavior for sending, streaming, cancellation, empty
  state suggestions, and errors.
- Render tool activity as structured action UI inside the chat instead of only a
  bottom status bar.
- Add real confirm/cancel behavior for sensitive backend tools using persisted
  `confirmation_id` records.
- Keep tool execution owned by the backend. Flutter displays and resolves
  confirmations; it does not execute SupaNotes tools directly.

## Non-Goals

- Do not move tool implementations into Flutter.
- Do not ask the model to infer confirmation from a follow-up natural-language
  message.
- Do not redesign the agent loop beyond the confirmation continuation needed for
  approved tools.
- Do not introduce Riverpod codegen or `StateNotifier`.

## Frontend Design

### Dependencies

Update `pubspec.yaml`:

- Remove `flutter_chat_core`.
- Remove `flutter_chat_ui`.
- Add `flutter_gen_ai_chat_ui: ^2.14.0`.

Run `flutter pub get` after the dependency change and update lockfile output.

### Chat Rendering

`AgentChatView` remains the local feature boundary, but its internals switch to
`AiChatWidget`.

The widget owns a `ChatMessagesController` from `flutter_gen_ai_chat_ui` and
synchronizes it from app-owned `ChatState`. The app continues to treat
`ChatController` as the source of truth. The package controller is a rendering
adapter, not the business state owner.

Configuration:

- `currentUser`: stable SupaNotes user id such as `agent-chat-current-user`.
- `aiUser`: stable assistant id such as `agent-chat-assistant`.
- `onSendMessage`: forwards message text to `ChatController.sendMessage`.
- `loadingConfig.isLoading`: mirrors `ChatState.isStreaming`.
- `onCancelGenerating`: calls `ChatController.cancelStreaming`.
- `inputOptions`: native input with `hintText: 'Mensagem...'`,
  `sendOnEnter: true`, and newline-friendly input behavior.
- `enableMarkdownStreaming: true`.
- `streamingWordByWord: true`.
- `exampleQuestions`: current quick prompts.
- `welcomeMessageConfig`: replaces the current custom empty state.

The current `ChatInput` widget becomes dead code and should be removed if no
other file uses it after migration.

### Message Adapter

Replace `toFlyerMessages` with an adapter that converts:

- user messages to `ChatMessage(text: ..., user: currentUser, ...)`
- assistant messages to `ChatMessage(text: ..., user: aiUser, ...)`
- system messages to informational assistant-side messages with a distinct
  `customProperties['role'] = 'system'`
- persisted tool messages to informational assistant-side messages with
  `customProperties['role'] = 'tool'`
- action events to rich/action messages with stable ids

Every converted message must carry a stable id in `customProperties`, using the
existing `MessageModel.id` or a deterministic action id. Streaming updates must
reuse the same assistant id so `ChatMessagesController.updateMessage` replaces
the in-flight assistant bubble in place.

### Chat State Shape

Replace `activeToolLabel` with structured action state. A record-based state is
still acceptable under the project Riverpod rules.

Proposed additions:

```dart
typedef ChatToolAction = ({
  String id,
  String name,
  String label,
  ChatToolActionStatus status,
  String? message,
  String? confirmationId,
});

enum ChatToolActionStatus {
  running,
  completed,
  failed,
  confirmationRequired,
  confirmed,
  cancelled,
}
```

`ChatState` should include `List<ChatToolAction> actions`. The controller appends
or updates actions as SSE events arrive:

- `tool_started`: add or mark action `running`.
- `tool_finished`: mark matching action `completed`.
- `tool_failed`: mark matching action `failed` with message.
- `confirmation_required`: add or mark action `confirmationRequired` with
  `confirmationId`.
- confirmation resolve success: mark `confirmed` or `cancelled`.

The old `errorMessage` remains for stream/API failures and user-visible errors
that are not action confirmations.

### Confirmation UI

When an action has `confirmationRequired`, render an inline card with:

- action label
- short text that this action needs approval
- Confirm button
- Cancel button
- disabled/loading state while the resolve request is in flight

Confirm calls `ChatController.resolveToolConfirmation(confirmationId, approved:
true)`. Cancel calls the same method with `approved: false`.

If the resolve request fails, keep the card visible and surface the error via
`ChatState.errorMessage` so existing messages and actions remain visible.

## Backend Design

### Database

Add migration `000017_pending_tool_confirmations`.

Table:

```sql
CREATE TABLE pending_tool_confirmations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL,
  tool_name TEXT NOT NULL,
  args_json JSONB NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'cancelled', 'expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_pending_tool_confirmations_user_session
  ON pending_tool_confirmations(user_id, session_id);

CREATE INDEX idx_pending_tool_confirmations_pending
  ON pending_tool_confirmations(user_id, status)
  WHERE status = 'pending';
```

The down migration drops the table.

### SQLC Queries

Extend `backend/db/queries/agent.sql`:

- `CreatePendingToolConfirmation`
- `GetPendingToolConfirmationForUpdate`
- `ResolvePendingToolConfirmation`

The get query must scope by confirmation id and user id. The resolve path must
reject non-pending confirmations.

### SSE Contract

Extend `ConfirmationRequiredPayload`:

```go
type ConfirmationRequiredPayload struct {
    ConfirmationID string `json:"confirmation_id"`
    ToolName       string `json:"tool_name"`
    Label          string `json:"label"`
}
```

Do not send raw `args_json` to Flutter in the event. The backend stores the
arguments and resolves by id.

### Agent Loop

When a sensitive tool is requested:

1. Create a pending confirmation row.
2. Emit `confirmation_required` with `confirmation_id`, `tool_name`, and label.
3. Emit `message_finished` with the existing confirmation text.
4. Return without executing the tool.

This preserves the current loop behavior while making the pending action
resolvable.

### Resolve Endpoint

Add:

`POST /api/v1/agent/tool-confirmations/:id/resolve`

Request:

```json
{ "approved": true }
```

Response:

```json
{
  "confirmation_id": "uuid",
  "status": "approved",
  "message": "..."
}
```

Behavior:

- Validate authenticated user.
- Load pending confirmation for that user.
- If not found, return 404.
- If already resolved, return 409.
- If `approved=false`, mark cancelled and return a cancellation message.
- If `approved=true`, execute the stored tool with stored args.
- Persist the tool result as a `tool` message.
- Mark approved if execution succeeds.
- If execution fails, mark the confirmation `cancelled`, return a 500 with the
  tool error message, and do not retry automatically. A separate retry contract
  can be added later if needed.

For the first implementation, approved confirmation returns the raw tool result
message. A later enhancement can resume the LLM loop to summarize the tool
result in natural language.

## API Client

Add a method to `ChatRepository` or a dedicated agent repository method:

```dart
Future<ToolConfirmationResolution> resolveToolConfirmation({
  required String confirmationId,
  required bool approved,
});
```

The response model should be a small typed object, not an untyped map passed
through widgets.

## Cleanup

Remove frontend dead code after migration:

- `lib/features/agent/presentation/widgets/chat_input.dart` if unused.
- Old `flutter_chat_*` adapter code.
- Old tests that only assert `flutter_chat_ui` implementation details.
- `flutter_chat_core` and `flutter_chat_ui` dependencies.

Do not remove backend tool execution code. It remains the owner of SupaNotes
tool behavior.

## Testing Plan

Frontend focused tests:

- message adapter maps user and assistant messages to `ChatMessage` with stable
  ids
- streaming assistant content updates the same message id
- empty chat renders package welcome/example questions
- native input sends through `ChatController`
- loading state exposes cancel generation
- `confirmation_required` renders an action card with Confirm and Cancel
- Confirm/Cancel call the resolve repository method with the right id and
  approval value
- failed confirmation resolve keeps the action visible and surfaces an error

Controller tests:

- `tool_started` appends a running action
- `tool_finished` marks it completed
- `tool_failed` stores the failure message
- `confirmation_required` stores `confirmationId`
- resolving approved appends/updates a result message and action status
- resolving cancelled marks the action cancelled

Backend tests:

- migration/query coverage for creating and resolving pending confirmations
- sensitive tool creates a pending confirmation and emits `confirmation_id`
- raw args are not emitted to the client
- approve executes the stored tool once
- cancel does not execute the tool
- resolving another user's confirmation returns 404
- resolving an already resolved confirmation returns 409

Verification commands:

```bash
flutter test test/features/agent
dart analyze lib/features/agent test/features/agent
go test ./internal/agent/... ./internal/db/...
```

Adjust exact package paths if backend tests require broader dependencies.

## Risks

- `flutter_gen_ai_chat_ui` API may require small adapter changes once installed.
  Validate with `flutter pub get` and compile before broad refactoring.
- The package action system is designed for local action execution. SupaNotes
  will use it primarily as a rich visual layer for backend-owned actions.
- Confirmation approval has side effects. The backend must resolve by persisted
  id and authenticated user, never by trusting client-returned arguments.
- Re-entering the LLM loop after approval is intentionally deferred to avoid
  combining package migration with a larger agent reasoning redesign.

## Acceptance Criteria

- The chat screen builds and runs with `flutter_gen_ai_chat_ui`.
- The old chat packages are no longer dependencies.
- User messages send through the native package input.
- Assistant responses stream into a stable assistant bubble.
- Stop generation cancels the current SSE request.
- Tool activity appears as structured inline action UI.
- Sensitive actions show Confirm and Cancel buttons.
- Confirming a sensitive action executes the persisted backend tool call.
- Cancelling a sensitive action does not execute the tool.
- Tests cover the new adapter, controller states, confirmation endpoint, and
  backend pending confirmation lifecycle.
