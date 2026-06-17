# Plan 023: Normalize the Agent Chat Stream Contract

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report; do not improvise. When done, update the status row for this plan
> in `plans/README.md` unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2488f1d..HEAD -- backend/internal/agent/handler.go backend/internal/agent/loop.go lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart test/features/agent`
>
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `2488f1d`, 2026-06-17

## Why this matters

The agent chat stream currently uses multiple JSON shapes for different event
types. The backend emits `content_delta`, `tool_use`, `tool_result`, and
`done`, while the handler rewrites each event into a different payload shape.
The Flutter parser then infers semantics from `delta`, `done`, or `type/data`.
This makes future chat UI work brittle: tool activity, retry, cancel, and error
recovery all depend on a contract that is not explicit.

This plan creates the smallest useful vertical slice: one normalized SSE event
envelope on the backend and a typed Flutter parser for that envelope. It does
not refactor the whole chat controller or add confirmation UX. Those should
come after this contract lands.

## Current state

Relevant files:

- `backend/internal/agent/loop.go` - owns the agent loop and emits internal `SSEEvent` values.
- `backend/internal/agent/handler.go` - converts `SSEEvent` values into wire SSE `data:` lines.
- `lib/features/agent/domain/sse_chat_event.dart` - parses stream JSON on Flutter.
- `lib/features/agent/data/chat_sse.dart` - opens `POST /agent/chat/stream` and yields parsed events.
- `test/features/agent/presentation` - existing Flutter agent tests.

Current backend loop event emission:

```go
// backend/internal/agent/loop.go:33-40
type SSEEvent struct {
	Type string
	Data string
}

func sendEvent(events chan<- SSEEvent, typ, data string) {
	if events != nil {
		events <- SSEEvent{Type: typ, Data: data}
	}
}
```

```go
// backend/internal/agent/loop.go:135-152
if res.Content != "" {
	sendEvent(events, "content_delta", res.Content)
}

if len(res.ToolCalls) > 0 {
	for _, tc := range res.ToolCalls {
		tcJSON, marshalErr := json.Marshal(tc)
		if marshalErr != nil {
			slog.Error("marshal tool call", "error", marshalErr)
			continue
		}
		sendEvent(events, "tool_use", string(tcJSON))
	}
}

if len(res.ToolCalls) == 0 {
	finalContent = res.Content
	sendEvent(events, "done", finalContent)
	break
}
```

Current handler rewrites events into incompatible JSON shapes:

```go
// backend/internal/agent/handler.go:100-110
for event := range events {
	var payload []byte
	switch event.Type {
	case "content_delta":
		payload, _ = json.Marshal(map[string]string{"delta": event.Data})
	case "done":
		payload, _ = json.Marshal(map[string]bool{"done": true})
	default:
		payload, _ = json.Marshal(map[string]string{"type": event.Type, "data": event.Data})
	}
	_, err := fmt.Fprintf(c.Response().Writer, "data: %s\n\n", payload)
```

Current Flutter parser mirrors those special cases:

```dart
// lib/features/agent/domain/sse_chat_event.dart:14-31
factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
  if (json.containsKey('delta')) {
    return SSEChatEvent(
      type: 'content_delta',
      delta: json['delta'] as String?,
    );
  } else if (json['done'] == true) {
    return SSEChatEvent(
      type: 'done',
      done: true,
    );
  } else if (json.containsKey('type')) {
    return SSEChatEvent(
      type: json['type'] as String? ?? 'unknown',
      data: json['data'] as String?,
    );
  }
  return SSEChatEvent(type: 'unknown');
}
```

Repo conventions to follow:

- Flutter providers are manual Riverpod providers. Do not use codegen.
- Existing chat tests use `flutter_test` and provider overrides; model new tests after `test/features/agent/presentation/chat_message_adapter_test.dart`.
- Backend tests use standard Go `testing` with small local fakes; model new tests after `backend/internal/agent/context_test.go`.
- Commit messages are conventional commits, for example `fix(notes): handle inbox and editor regressions`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Backend focused tests | `go test ./internal/agent/...` from `backend/` | exit 0 |
| Flutter focused tests | `flutter test test/features/agent` | all tests pass |
| Flutter focused analysis | `dart analyze lib/features/agent test/features/agent` | no issues found |
| Git status | `git status --short` | only in-scope files changed |

## Scope

**In scope**:

- `backend/internal/agent/events.go` (create)
- `backend/internal/agent/events_test.go` (create)
- `backend/internal/agent/loop.go`
- `backend/internal/agent/handler.go`
- `lib/features/agent/domain/sse_chat_event.dart`
- `lib/features/agent/data/chat_sse.dart`
- `test/features/agent/domain/sse_chat_event_test.dart` (create)

**Out of scope**:

- `lib/features/agent/presentation/controllers/chat_controller.dart` - keep its current string checks working through compatibility getters.
- `lib/features/agent/presentation/widgets/agent_chat_view.dart` - no UI changes in this plan.
- Tool confirmation policy and risk metadata - separate plan after this contract lands.
- Prompt/context rewriting - separate plan after stream contract work.
- Any note editor, note card, or note stylesheet files currently dirty in the worktree.

## Git workflow

- Branch: `feat/agent-chat-stream-contract`
- Commit message: `feat(agent): normalize chat stream events`
- Do not push or open a PR unless the operator explicitly asks.
- Do not stage unrelated dirty files.

## Steps

### Step 1: Add backend event envelope tests

Create `backend/internal/agent/events_test.go`:

```go
package agent

import (
	"encoding/json"
	"testing"
)

func TestStreamEventEnvelopeMarshal(t *testing.T) {
	event := StreamEvent{
		SessionID: "session-1",
		MessageID: "message-1",
		Sequence:  7,
		Type:      EventContentDelta,
		Payload:   ContentDeltaPayload{Delta: "Oi"},
	}

	body, err := json.Marshal(event)
	if err != nil {
		t.Fatalf("marshal event: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decode event: %v", err)
	}

	if decoded["session_id"] != "session-1" {
		t.Fatalf("session_id: got %#v", decoded["session_id"])
	}
	if decoded["message_id"] != "message-1" {
		t.Fatalf("message_id: got %#v", decoded["message_id"])
	}
	if decoded["sequence"].(float64) != 7 {
		t.Fatalf("sequence: got %#v", decoded["sequence"])
	}
	if decoded["type"] != string(EventContentDelta) {
		t.Fatalf("type: got %#v", decoded["type"])
	}
	if decoded["payload"] == nil {
		t.Fatal("payload missing")
	}
}

func TestStreamEventWriterIncrementsSequence(t *testing.T) {
	writer := NewStreamEventWriter("session-1", "message-1")

	first := writer.Event(EventMessageStarted, map[string]string{"role": "assistant"})
	second := writer.Event(EventMessageFinished, MessageFinishedPayload{Content: "Pronto"})

	if first.Sequence != 1 {
		t.Fatalf("first sequence: want 1, got %d", first.Sequence)
	}
	if second.Sequence != 2 {
		t.Fatalf("second sequence: want 2, got %d", second.Sequence)
	}
}
```

**Verify**: From `backend/`, run:

```powershell
go test ./internal/agent -run TestStreamEvent
```

Expected: FAIL with undefined `StreamEvent`, `EventContentDelta`, and `NewStreamEventWriter`.

### Step 2: Add backend event contract types

Create `backend/internal/agent/events.go`:

```go
package agent

type EventType string

const (
	EventMessageStarted  EventType = "message_started"
	EventContentDelta    EventType = "content_delta"
	EventToolStarted     EventType = "tool_started"
	EventToolFinished    EventType = "tool_finished"
	EventToolFailed      EventType = "tool_failed"
	EventMessageFinished EventType = "message_finished"
	EventError           EventType = "error"
)

type StreamEvent struct {
	SessionID string      `json:"session_id"`
	MessageID string      `json:"message_id"`
	Sequence  int         `json:"sequence"`
	Type      EventType   `json:"type"`
	Payload   interface{} `json:"payload"`
}

type ContentDeltaPayload struct {
	Delta string `json:"delta"`
}

type ToolActivityPayload struct {
	Name  string `json:"name"`
	Label string `json:"label"`
}

type ToolFailedPayload struct {
	Name    string `json:"name"`
	Label   string `json:"label"`
	Message string `json:"message"`
}

type MessageFinishedPayload struct {
	Content string `json:"content"`
}

type ErrorPayload struct {
	Message string `json:"message"`
}

type StreamEventWriter struct {
	sessionID string
	messageID string
	sequence  int
}

func NewStreamEventWriter(sessionID, messageID string) *StreamEventWriter {
	return &StreamEventWriter{sessionID: sessionID, messageID: messageID}
}

func (w *StreamEventWriter) Event(typ EventType, payload interface{}) StreamEvent {
	w.sequence++
	return StreamEvent{
		SessionID: w.sessionID,
		MessageID: w.messageID,
		Sequence:  w.sequence,
		Type:      typ,
		Payload:   payload,
	}
}
```

**Verify**: From `backend/`, run:

```powershell
go test ./internal/agent -run TestStreamEvent
```

Expected: PASS.

### Step 3: Emit normalized events from the backend loop

In `backend/internal/agent/loop.go`, add this helper near `sendEvent`:

```go
func sendStreamEvent(events chan<- SSEEvent, event StreamEvent) {
	if events == nil {
		return
	}
	payload, err := json.Marshal(event)
	if err != nil {
		slog.Error("marshal stream event", "error", err)
		return
	}
	events <- SSEEvent{Type: string(event.Type), Data: string(payload)}
}
```

Inside `doChat`, after `sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}`, add:

```go
assistantMessageID := uuid.NewString()
writer := NewStreamEventWriter(sessionIDStr, assistantMessageID)
sendStreamEvent(events, writer.Event(
	EventMessageStarted,
	map[string]string{"role": string(llm.RoleAssistant)},
))
```

Replace the `sendEvent(events, "content_delta", res.Content)` block with:

```go
if res.Content != "" {
	sendStreamEvent(events, writer.Event(
		EventContentDelta,
		ContentDeltaPayload{Delta: res.Content},
	))
}
```

Replace `tool_use` send with:

```go
sendStreamEvent(events, writer.Event(
	EventToolStarted,
	ToolActivityPayload{Name: tc.Name, Label: labelForTool(tc.Name)},
))
```

Add this private helper in `loop.go`:

```go
func labelForTool(toolName string) string {
	switch toolName {
	case "search_notes":
		return "Buscando notas"
	case "get_note", "get_notes":
		return "Lendo notas"
	case "get_open_tasks", "get_today_tasks":
		return "Consultando tarefas"
	case "add_note", "append_to_note", "append_to_inbox":
		return "Atualizando notas"
	case "add_task", "update_task", "complete_task":
		return "Atualizando tarefas"
	default:
		return "Executando acao"
	}
}
```

In the tool execution loop, emit finished or failed after `Execute`:

```go
resultStr, err := l.tools.Execute(ctx, userID, tc.Name, tc.ArgsJSON)
if err != nil {
	resultStr = fmt.Sprintf("Error executing tool: %v", err)
	sendStreamEvent(events, writer.Event(
		EventToolFailed,
		ToolFailedPayload{Name: tc.Name, Label: labelForTool(tc.Name), Message: err.Error()},
	))
} else {
	sendStreamEvent(events, writer.Event(
		EventToolFinished,
		ToolActivityPayload{Name: tc.Name, Label: labelForTool(tc.Name)},
	))
}
```

Replace both `sendEvent(events, "done", finalContent)` calls with:

```go
sendStreamEvent(events, writer.Event(
	EventMessageFinished,
	MessageFinishedPayload{Content: finalContent},
))
```

Update `Chat` compatibility in `loop.go` so the old synchronous endpoint still returns assistant text, not the raw event envelope. Replace the goroutine loop that currently checks `evt.Type == "content_delta" || evt.Type == "done"` with:

```go
for evt := range events {
	switch EventType(evt.Type) {
	case EventContentDelta:
		var event StreamEvent
		if err := json.Unmarshal([]byte(evt.Data), &event); err != nil {
			continue
		}
		payloadBytes, err := json.Marshal(event.Payload)
		if err != nil {
			continue
		}
		var payload ContentDeltaPayload
		if err := json.Unmarshal(payloadBytes, &payload); err != nil {
			continue
		}
		ch <- payload.Delta
	case EventMessageFinished:
		var event StreamEvent
		if err := json.Unmarshal([]byte(evt.Data), &event); err != nil {
			continue
		}
		payloadBytes, err := json.Marshal(event.Payload)
		if err != nil {
			continue
		}
		var payload MessageFinishedPayload
		if err := json.Unmarshal(payloadBytes, &payload); err != nil {
			continue
		}
		ch <- payload.Content
	}
}
```

Do not remove `/agent/chat` in this plan.

**Verify**: From `backend/`, run:

```powershell
go test ./internal/agent/...
```

Expected: PASS. If the synchronous `Chat` path test fails because it receives an envelope, STOP and report; do not delete the endpoint.

### Step 4: Let the handler write normalized envelopes directly

In `backend/internal/agent/handler.go`, remove `encoding/json` from imports if it becomes unused.

Replace the error event inside the goroutine:

```go
if err := h.loop.ChatStream(c.Request().Context(), userID, req.SessionID, req.Content, events); err != nil {
	writer := NewStreamEventWriter(req.SessionID, "")
	sendStreamEvent(events, writer.Event(EventError, ErrorPayload{Message: err.Error()}))
}
```

Replace the switch in the `for event := range events` loop with:

```go
for event := range events {
	_, err := fmt.Fprintf(c.Response().Writer, "data: %s\n\n", event.Data)
	if err != nil {
		break
	}
	flusher.Flush()
}
```

**Verify**: From `backend/`, run:

```powershell
go test ./internal/agent/...
```

Expected: PASS.

### Step 5: Add Flutter parser tests

Create `test/features/agent/domain/sse_chat_event_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';

void main() {
  test('parses normalized content delta event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 2,
      'type': 'content_delta',
      'payload': {'delta': 'Oi'},
    });

    expect(event.type, 'content_delta');
    expect(event.sessionId, 'session-1');
    expect(event.messageId, 'message-1');
    expect(event.sequence, 2);
    expect(event.delta, 'Oi');
    expect(event.isContentDelta, isTrue);
  });

  test('parses normalized tool started event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 3,
      'type': 'tool_started',
      'payload': {'name': 'search_notes', 'label': 'Buscando notas'},
    });

    expect(event.type, 'tool_started');
    expect(event.toolName, 'search_notes');
    expect(event.toolLabel, 'Buscando notas');
    expect(event.isToolStarted, isTrue);
  });

  test('parses normalized message finished event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 4,
      'type': 'message_finished',
      'payload': {'content': 'Pronto'},
    });

    expect(event.finalContent, 'Pronto');
    expect(event.isDone, isTrue);
  });
}
```

**Verify**:

```powershell
flutter test test/features/agent/domain/sse_chat_event_test.dart
```

Expected: FAIL because the parser does not expose identity fields or normalized payload accessors yet.

### Step 6: Update the Flutter event parser with compatibility getters

Replace `lib/features/agent/domain/sse_chat_event.dart` with:

```dart
class SSEChatEvent {
  const SSEChatEvent({
    required this.type,
    this.sessionId = '',
    this.messageId = '',
    this.sequence = 0,
    this.payload = const {},
  });

  final String type;
  final String sessionId;
  final String messageId;
  final int sequence;
  final Map<String, dynamic> payload;

  factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (payload is Map<String, dynamic>) {
      return SSEChatEvent(
        type: json['type'] as String? ?? 'unknown',
        sessionId: json['session_id'] as String? ?? '',
        messageId: json['message_id'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        payload: payload,
      );
    }

    if (json.containsKey('delta')) {
      return SSEChatEvent(
        type: 'content_delta',
        payload: {'delta': json['delta']},
      );
    }
    if (json['done'] == true) {
      return const SSEChatEvent(type: 'message_finished');
    }
    if (json.containsKey('type')) {
      return SSEChatEvent(
        type: json['type'] as String? ?? 'unknown',
        payload: {'data': json['data']},
      );
    }
    return const SSEChatEvent(type: 'unknown');
  }

  String? get delta => payload['delta'] as String?;
  String? get data => payload['data'] as String?;
  String? get toolName => payload['name'] as String?;
  String? get toolLabel => payload['label'] as String?;
  String? get errorMessage => payload['message'] as String?;
  String? get finalContent => payload['content'] as String?;

  bool get isContentDelta => type == 'content_delta';
  bool get isToolUse => type == 'tool_use' || type == 'tool_started';
  bool get isToolResult => type == 'tool_result' || type == 'tool_finished';
  bool get isToolStarted => type == 'tool_started';
  bool get isToolFinished => type == 'tool_finished';
  bool get isToolFailed => type == 'tool_failed';
  bool get isDone => type == 'done' || type == 'message_finished';
  bool get isError => type == 'error';
}
```

This intentionally keeps `type` as `String` and preserves existing getters so
`ChatController` does not need to change in this plan.

**Verify**:

```powershell
flutter test test/features/agent/domain/sse_chat_event_test.dart
dart analyze lib/features/agent/domain/sse_chat_event.dart test/features/agent/domain/sse_chat_event_test.dart
```

Expected: PASS and no analyzer issues.

### Step 7: Update `ChatSSE` termination and error handling

In `lib/features/agent/data/chat_sse.dart`, replace direct string checks with getters:

```dart
if (event.isError) {
  controller.addError(
    ApiException(message: event.errorMessage ?? event.data ?? 'Ocorreu um erro no stream'),
  );
  break;
}

controller.add(event);

if (event.isDone) {
  break;
}
```

Replace the current `catchError` body:

```dart
}).catchError((Object e) {
  if (e is DioException && CancelToken.isCancel(e)) return;
  controller.addError(fromDioError(e as DioException));
  controller.close();
});
```

with:

```dart
}).catchError((Object e) {
  if (e is DioException) {
    if (CancelToken.isCancel(e)) return;
    controller.addError(fromDioError(e));
  } else {
    controller.addError(ApiException(message: e.toString()));
  }
  controller.close();
});
```

**Verify**:

```powershell
flutter test test/features/agent
dart analyze lib/features/agent test/features/agent
```

Expected: PASS and no analyzer issues.

### Step 8: Final verification and commit

Run:

```powershell
git status --short
```

Expected: only these files are modified or created:

```text
backend/internal/agent/events.go
backend/internal/agent/events_test.go
backend/internal/agent/loop.go
backend/internal/agent/handler.go
lib/features/agent/domain/sse_chat_event.dart
lib/features/agent/data/chat_sse.dart
test/features/agent/domain/sse_chat_event_test.dart
plans/README.md
plans/023-normalize-agent-chat-stream-contract.md
```

If unrelated files appear, do not stage them.

Commit:

```powershell
git add backend/internal/agent/events.go backend/internal/agent/events_test.go backend/internal/agent/loop.go backend/internal/agent/handler.go lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart test/features/agent/domain/sse_chat_event_test.dart
git commit -m "feat(agent): normalize chat stream events"
```

Expected: commit succeeds.

## Test plan

- New backend tests:
  - `backend/internal/agent/events_test.go`
  - Covers event envelope JSON and sequence incrementing.
- New Flutter tests:
  - `test/features/agent/domain/sse_chat_event_test.dart`
  - Covers normalized `content_delta`, `tool_started`, and `message_finished`.
- Existing tests:
  - `go test ./internal/agent/...`
  - `flutter test test/features/agent`
  - `dart analyze lib/features/agent test/features/agent`

## Done criteria

- [ ] Backend emits one normalized JSON envelope for all stream event types.
- [ ] Handler writes `event.Data` directly as the SSE `data:` payload.
- [ ] Flutter parser supports normalized payloads and keeps old compatibility getters.
- [ ] Existing chat controller compiles without being refactored.
- [ ] `go test ./internal/agent/...` passes from `backend/`.
- [ ] `flutter test test/features/agent` passes.
- [ ] `dart analyze lib/features/agent test/features/agent` reports no issues.
- [ ] No unrelated dirty files are staged.

## STOP conditions

Stop and report back if:

- `backend/internal/agent/loop.go` no longer contains `sendEvent`, `ChatStream`, or `doChat` in the shape shown above.
- The synchronous `/agent/chat` endpoint starts returning an event envelope instead of assistant text and the compatibility parsing above does not fix it.
- The frontend controller must be refactored to compile. That belongs in the next plan.
- Backend tests require a live LLM or database connection.
- Any fix requires editing note editor/card/stylesheet files or other unrelated dirty files.

## Maintenance notes

This plan deliberately preserves compatibility in `SSEChatEvent` so the UI can keep working while the contract changes underneath it. A follow-up plan should refactor `ChatController` to stop comparing raw strings and to expose explicit `activeToolLabel`, `errorMessage`, `retryMessage`, and cancel state. Another follow-up should move tool labels and risk classification into `ToolRegistry` instead of keeping `labelForTool` local to `loop.go`.
