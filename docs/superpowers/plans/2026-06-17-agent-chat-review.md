# Agent Chat Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a typed agent chat contract with clearer streaming state, readable tool activity, safer tool execution policy, and focused tests across the Go backend and Flutter frontend.

**Architecture:** Normalize backend SSE events first, then make the Flutter parser and controller consume typed events instead of inferred strings. Keep the existing agent loop, `flutter_chat_ui`, Riverpod manual providers, and current repositories, but split transient chat state from persisted message content and add explicit tool risk metadata for confirmation-aware behavior.

**Tech Stack:** Go (Echo, sqlc, pgx, current `pkg/llm` interfaces), Flutter (Riverpod 3 manual providers, Dio streams, `flutter_chat_ui`, existing SupaNotes theme/widgets).

---

## File Structure

- Create: `backend/internal/agent/events.go`
  - Owns typed SSE event names, payload structs, sequence generation helpers, and JSON encoding for stream events.
- Modify: `backend/internal/agent/handler.go`
  - Writes normalized event envelopes for every SSE event instead of switching JSON shape by event type.
- Modify: `backend/internal/agent/loop.go`
  - Emits `message_started`, `content_delta`, `tool_started`, `tool_finished`, `tool_failed`, `message_finished`, and `error`.
  - Keeps the existing LLM/tool loop and persistence behavior in this phase.
- Modify: `backend/internal/agent/tools/registry.go`
  - Adds tool risk metadata and human labels for UI-facing tool activity.
- Create: `backend/internal/agent/events_test.go`
  - Verifies event envelope JSON shape and sequence behavior.
- Create: `backend/internal/agent/loop_test.go`
  - Verifies stream event ordering with a fake LLM client and fake tool registry path.
- Modify: `backend/internal/agent/context.go`
  - Structures prompt/context output into named sections and adds tool-use rules.
- Modify: `backend/internal/agent/context_test.go`
  - Verifies context sections are present and ordered.
- Modify: `lib/features/agent/domain/sse_chat_event.dart`
  - Replaces the loose parser with typed event names, payload accessors, and compatibility parsing during rollout.
- Create: `test/features/agent/domain/sse_chat_event_test.dart`
  - Verifies every normalized backend event parses correctly.
- Modify: `lib/features/agent/data/chat_sse.dart`
  - Yields typed events, surfaces malformed stream errors deliberately, and supports cancellation.
- Create: `test/features/agent/data/chat_sse_test.dart`
  - Verifies stream parsing, error event handling, and cancel behavior with a Dio test adapter or small fake `ApiClient`.
- Modify: `lib/features/agent/presentation/controllers/chat_controller.dart`
  - Replaces ad hoc string status with explicit chat state: active tool, partial response, recoverable error, retry and cancel availability.
- Create: `test/features/agent/presentation/controllers/chat_controller_test.dart`
  - Verifies state transitions for history load, content stream, tool activity, errors, retry, and cancel.
- Modify: `lib/features/agent/presentation/widgets/agent_chat_view.dart`
  - Renders tool activity, inline error/retry, cancel, and improved empty prompt suggestions.
- Modify: `lib/features/agent/presentation/widgets/chat_input.dart`
  - Keeps composer behavior but accepts optional trailing action state only if needed by `AgentChatView`.
- Modify: `test/features/agent/presentation/widgets/agent_chat_view_test.dart`
  - Adds widget coverage for tool activity, inline error, retry, cancel, and empty suggestions.
- Modify: `lib/features/agent/presentation/chat_screen.dart`
  - Wires new state fields to `AgentChatView`.
- Modify: `test/features/agent/presentation/chat_screen_test.dart`
  - Keeps screen integration coverage current.
- Create: `task.md`
  - Tracks execution progress only after implementation starts.

---

### Task 1: Add Backend Stream Event Contract

**Files:**
- Create: `backend/internal/agent/events.go`
- Create: `backend/internal/agent/events_test.go`
- Modify: `backend/internal/agent/handler.go`

- [ ] **Step 1: Write failing event envelope tests**

Create `backend/internal/agent/events_test.go`:

```go
package agent

import (
	"encoding/json"
	"testing"
)

func TestNewSSEWriterEvent_IncrementsSequenceAndEncodesEnvelope(t *testing.T) {
	writer := NewSSEEventWriter("session-1", "message-1")

	first := writer.Event(EventMessageStarted, map[string]string{"role": "assistant"})
	second := writer.Event(EventContentDelta, ContentDeltaPayload{Delta: "Oi"})

	if first.Sequence != 1 {
		t.Fatalf("first sequence: want 1, got %d", first.Sequence)
	}
	if second.Sequence != 2 {
		t.Fatalf("second sequence: want 2, got %d", second.Sequence)
	}
	if second.SessionID != "session-1" || second.MessageID != "message-1" {
		t.Fatalf("unexpected identity fields: %#v", second)
	}

	body, err := json.Marshal(second)
	if err != nil {
		t.Fatalf("marshal event: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decode event: %v", err)
	}
	if decoded["type"] != string(EventContentDelta) {
		t.Fatalf("type: want %q, got %#v", EventContentDelta, decoded["type"])
	}
	if decoded["payload"] == nil {
		t.Fatal("expected payload object")
	}
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```powershell
go test ./internal/agent -run TestNewSSEWriterEvent_IncrementsSequenceAndEncodesEnvelope
```

Expected: FAIL with `undefined: NewSSEEventWriter` and missing event constants.

- [ ] **Step 3: Add event contract implementation**

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

type SSEEventWriter struct {
	sessionID string
	messageID string
	sequence  int
}

func NewSSEEventWriter(sessionID, messageID string) *SSEEventWriter {
	return &SSEEventWriter{sessionID: sessionID, messageID: messageID}
}

func (w *SSEEventWriter) Event(typ EventType, payload interface{}) StreamEvent {
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

- [ ] **Step 4: Run event tests**

Run:

```powershell
go test ./internal/agent -run TestNewSSEWriterEvent_IncrementsSequenceAndEncodesEnvelope
```

Expected: PASS.

- [ ] **Step 5: Commit backend event contract**

Run:

```powershell
git add backend/internal/agent/events.go backend/internal/agent/events_test.go
git commit -m "feat(agent): add typed stream event contract"
```

Expected: commit succeeds on a clean feature branch.

---

### Task 2: Emit Normalized Backend Events

**Files:**
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/handler.go`
- Create: `backend/internal/agent/loop_test.go`

- [ ] **Step 1: Write failing loop event-order test**

Create `backend/internal/agent/loop_test.go` with a narrow test around event emission:

```go
package agent

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type fakeAgentRepo struct {
	messages []sqlcgen.Message
}

func (r *fakeAgentRepo) GetMessages(context.Context, pgtype.UUID, pgtype.UUID, int32, int32) ([]sqlcgen.Message, error) {
	return r.messages, nil
}
func (r *fakeAgentRepo) CreateMessage(_ context.Context, _ pgtype.UUID, _ pgtype.UUID, role, content string, _ []byte, _ *string) (sqlcgen.Message, error) {
	return sqlcgen.Message{Role: role, Content: content}, nil
}
func (r *fakeAgentRepo) DeleteSessionMessages(context.Context, pgtype.UUID, pgtype.UUID) error { return nil }
func (r *fakeAgentRepo) CountNotes(context.Context, pgtype.UUID) (int64, error) { return 0, nil }
func (r *fakeAgentRepo) CountTasks(context.Context, pgtype.UUID) (int64, error) { return 0, nil }
func (r *fakeAgentRepo) CountOpenTasks(context.Context, pgtype.UUID) (int64, error) { return 0, nil }
func (r *fakeAgentRepo) CountCompletedTasks(context.Context, pgtype.UUID) (int64, error) { return 0, nil }

type fakeAgentClient struct{}

func (c fakeAgentClient) Complete(context.Context, llm.Request) (*llm.Response, error) {
	return &llm.Response{Content: "Resposta"}, nil
}

type fakeAgentFactory struct{}

func (f fakeAgentFactory) For(llm.TaskType) llm.Client { return fakeAgentClient{} }

func TestLoopChatStreamEmitsNormalizedEvents(t *testing.T) {
	loop := NewLoop(&fakeAgentRepo{}, fakeAgentFactory{}, &staticContextBuilder{}, NewToolRegistryForTests(nil))
	events := make(chan SSEEvent, 10)

	err := loop.ChatStream(
		context.Background(),
		pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
		"00000000-0000-0000-0000-000000000001",
		"Oi",
		events,
	)
	if err != nil {
		t.Fatalf("ChatStream: %v", err)
	}
	close(events)

	var types []string
	for event := range events {
		types = append(types, event.Type)
	}

	want := []string{"message_started", "content_delta", "message_finished"}
	if len(types) != len(want) {
		t.Fatalf("event count: want %d, got %d (%v)", len(want), len(types), types)
	}
	for i := range want {
		if types[i] != want[i] {
			t.Fatalf("event %d: want %s, got %s", i, want[i], types[i])
		}
	}
}
```

Also add the minimal test helper needed for the context builder. If `ContextBuilder` cannot be substituted directly, make the smallest production change first: extract an interface in `loop.go`:

```go
type contextBuilder interface {
	Build(ctx context.Context, userID, sessionID pgtype.UUID, query string) (string, error)
}
```

Then change `Loop.ctxBldr` from `*ContextBuilder` to `contextBuilder`.

Use this fake in the test:

```go
type staticContextBuilder struct{}

func (b *staticContextBuilder) Build(context.Context, pgtype.UUID, pgtype.UUID, string) (string, error) {
	return "SYSTEM RULES:\nUse concise answers.", nil
}
```

- [ ] **Step 2: Run the loop test and confirm it fails**

Run:

```powershell
go test ./internal/agent -run TestLoopChatStreamEmitsNormalizedEvents
```

Expected: FAIL because the loop still emits `done` instead of `message_finished` and does not emit `message_started`.

- [ ] **Step 3: Update `SSEEvent` and emission in `loop.go`**

In `backend/internal/agent/loop.go`, keep the existing channel type but emit normalized event types. Update `SSEEvent` to carry payload JSON strings:

```go
type SSEEvent struct {
	Type string
	Data string
}
```

Add a small helper:

```go
func sendPayloadEvent(events chan<- SSEEvent, typ EventType, payload string) {
	if events != nil {
		events <- SSEEvent{Type: string(typ), Data: payload}
	}
}
```

At the start of `doChat`, after parsing `sessionUUID`, create a local assistant message id:

```go
assistantMessageID := uuid.NewString()
writer := NewSSEEventWriter(sessionIDStr, assistantMessageID)
sendStreamEvent(events, writer.Event(EventMessageStarted, map[string]string{"role": string(llm.RoleAssistant)}))
```

Add this helper in `loop.go`:

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

Replace content and completion sends:

```go
if res.Content != "" {
	sendStreamEvent(events, writer.Event(EventContentDelta, ContentDeltaPayload{Delta: res.Content}))
}

if len(res.ToolCalls) == 0 {
	finalContent = res.Content
	sendStreamEvent(events, writer.Event(EventMessageFinished, MessageFinishedPayload{Content: finalContent}))
	break
}
```

For each tool call, emit start/finish/failure:

```go
label := l.tools.Label(tc.Name)
sendStreamEvent(events, writer.Event(EventToolStarted, ToolActivityPayload{Name: tc.Name, Label: label}))

resultStr, err := l.tools.Execute(ctx, userID, tc.Name, tc.ArgsJSON)
if err != nil {
	resultStr = fmt.Sprintf("Error executing tool: %v", err)
	sendStreamEvent(events, writer.Event(EventToolFailed, ToolFailedPayload{Name: tc.Name, Label: label, Message: err.Error()}))
} else {
	sendStreamEvent(events, writer.Event(EventToolFinished, ToolActivityPayload{Name: tc.Name, Label: label}))
}
```

For max iterations:

```go
finalContent = "Agent reached maximum iterations without final answer."
sendStreamEvent(events, writer.Event(EventMessageFinished, MessageFinishedPayload{Content: finalContent}))
```

- [ ] **Step 4: Add labels to `ToolRegistry`**

In `backend/internal/agent/tools/registry.go`, add a label lookup:

```go
func (tr *ToolRegistry) Label(toolName string) string {
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
	case "save_memory", "delete_memory", "list_memories":
		return "Consultando memórias"
	case "get_soul", "update_soul":
		return "Lendo preferências"
	case "plan_inbox_organization", "apply_inbox_organization":
		return "Organizando inbox"
	default:
		return "Executando ação"
	}
}
```

If the loop test needs an empty registry, add:

```go
func NewToolRegistryForTests(tools map[string]ToolExecutor) *ToolRegistry {
	if tools == nil {
		tools = make(map[string]ToolExecutor)
	}
	return &ToolRegistry{tools: tools}
}
```

- [ ] **Step 5: Normalize handler SSE writing**

In `backend/internal/agent/handler.go`, replace the event switch in `ChatSSE` with one path:

```go
for event := range events {
	_, err := fmt.Fprintf(c.Response().Writer, "data: %s\n\n", event.Data)
	if err != nil {
		break
	}
	flusher.Flush()
}
```

In the goroutine error path, create a normalized error event:

```go
writer := NewSSEEventWriter(req.SessionID, "")
sendStreamEvent(events, writer.Event(EventError, ErrorPayload{Message: err.Error()}))
```

- [ ] **Step 6: Run backend agent tests**

Run:

```powershell
go test ./internal/agent/...
```

Expected: PASS.

- [ ] **Step 7: Commit normalized backend streaming**

Run:

```powershell
git add backend/internal/agent/loop.go backend/internal/agent/handler.go backend/internal/agent/tools/registry.go backend/internal/agent/loop_test.go
git commit -m "feat(agent): emit normalized chat stream events"
```

Expected: commit succeeds.

---

### Task 3: Parse Typed Events In Flutter

**Files:**
- Modify: `lib/features/agent/domain/sse_chat_event.dart`
- Create: `test/features/agent/domain/sse_chat_event_test.dart`
- Modify: `lib/features/agent/data/chat_sse.dart`
- Create: `test/features/agent/data/chat_sse_test.dart`

- [ ] **Step 1: Write failing domain parser tests**

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

    expect(event.type, SSEChatEventType.contentDelta);
    expect(event.sessionId, 'session-1');
    expect(event.messageId, 'message-1');
    expect(event.sequence, 2);
    expect(event.delta, 'Oi');
  });

  test('parses normalized tool activity event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': 'message-1',
      'sequence': 3,
      'type': 'tool_started',
      'payload': {'name': 'search_notes', 'label': 'Buscando notas'},
    });

    expect(event.type, SSEChatEventType.toolStarted);
    expect(event.toolName, 'search_notes');
    expect(event.toolLabel, 'Buscando notas');
  });

  test('parses normalized error event', () {
    final event = SSEChatEvent.fromJson(const {
      'session_id': 'session-1',
      'message_id': '',
      'sequence': 1,
      'type': 'error',
      'payload': {'message': 'falhou'},
    });

    expect(event.type, SSEChatEventType.error);
    expect(event.errorMessage, 'falhou');
  });
}
```

- [ ] **Step 2: Run parser tests and confirm failure**

Run:

```powershell
flutter test test/features/agent/domain/sse_chat_event_test.dart
```

Expected: FAIL because `SSEChatEventType`, identity fields, and payload accessors do not exist yet.

- [ ] **Step 3: Replace `SSEChatEvent` with typed parser**

Replace `lib/features/agent/domain/sse_chat_event.dart` with:

```dart
enum SSEChatEventType {
  messageStarted,
  contentDelta,
  toolStarted,
  toolFinished,
  toolFailed,
  messageFinished,
  error,
  unknown,
}

class SSEChatEvent {
  const SSEChatEvent({
    required this.type,
    required this.sessionId,
    required this.messageId,
    required this.sequence,
    required this.payload,
  });

  final SSEChatEventType type;
  final String sessionId;
  final String messageId;
  final int sequence;
  final Map<String, dynamic> payload;

  factory SSEChatEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return SSEChatEvent(
      type: _typeFromString(json['type'] as String?),
      sessionId: json['session_id'] as String? ?? '',
      messageId: json['message_id'] as String? ?? '',
      sequence: json['sequence'] as int? ?? 0,
      payload: payload is Map<String, dynamic> ? payload : const {},
    );
  }

  String? get delta => payload['delta'] as String?;
  String? get toolName => payload['name'] as String?;
  String? get toolLabel => payload['label'] as String?;
  String? get errorMessage => payload['message'] as String?;
  String? get finalContent => payload['content'] as String?;
}

SSEChatEventType _typeFromString(String? value) {
  switch (value) {
    case 'message_started':
      return SSEChatEventType.messageStarted;
    case 'content_delta':
      return SSEChatEventType.contentDelta;
    case 'tool_started':
      return SSEChatEventType.toolStarted;
    case 'tool_finished':
      return SSEChatEventType.toolFinished;
    case 'tool_failed':
      return SSEChatEventType.toolFailed;
    case 'message_finished':
      return SSEChatEventType.messageFinished;
    case 'error':
      return SSEChatEventType.error;
    default:
      return SSEChatEventType.unknown;
  }
}
```

- [ ] **Step 4: Update `ChatSSE` error handling for typed errors**

In `lib/features/agent/data/chat_sse.dart`, update event checks:

```dart
final event = SSEChatEvent.fromJson(data);

if (event.type == SSEChatEventType.error) {
  controller.addError(
    ApiException(message: event.errorMessage ?? 'Ocorreu um erro no stream'),
  );
  break;
}

controller.add(event);

if (event.type == SSEChatEventType.messageFinished) {
  break;
}
```

In the `catchError`, avoid casting non-Dio errors blindly:

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

- [ ] **Step 5: Run parser and focused data tests**

Run:

```powershell
flutter test test/features/agent/domain/sse_chat_event_test.dart
dart analyze lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart
```

Expected: tests PASS and analyzer reports no issues.

- [ ] **Step 6: Commit Flutter parser changes**

Run:

```powershell
git add lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart test/features/agent/domain/sse_chat_event_test.dart
git commit -m "feat(agent): parse normalized chat stream events"
```

Expected: commit succeeds.

---

### Task 4: Refactor Chat Controller State

**Files:**
- Modify: `lib/features/agent/presentation/controllers/chat_controller.dart`
- Create: `test/features/agent/presentation/controllers/chat_controller_test.dart`

- [ ] **Step 1: Write failing controller test for tool activity and partial error**

Create `test/features/agent/presentation/controllers/chat_controller_test.dart` with provider overrides for a fake repository and fake stream client. If injecting `ChatSSE` is not currently possible, first add a provider for it in production:

```dart
final chatSSEProvider = Provider.autoDispose<ChatSSE>((ref) {
  return ChatSSE(apiClient: ref.watch(apiClientProvider));
});
```

Then use this test shape:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/agent/data/chat_repository.dart';
import 'package:supanotes/features/agent/data/chat_sse.dart';
import 'package:supanotes/features/agent/domain/message_model.dart';
import 'package:supanotes/features/agent/domain/session_manager.dart';
import 'package:supanotes/features/agent/domain/sse_chat_event.dart';
import 'package:supanotes/features/agent/presentation/controllers/chat_controller.dart';

class FakeChatRepository implements IChatRepository {
  @override
  Future<void> clearHistory(String sessionId) async {}

  @override
  Future<List<MessageModel>> getHistory(String sessionId) async => const [];

  @override
  Future<String> sendMessage({required String sessionId, required String message}) async => '';
}

class FakeChatSSE extends ChatSSE {
  FakeChatSSE(this.events) : super(apiClient: throw UnimplementedError());

  final Stream<SSEChatEvent> events;

  @override
  Stream<SSEChatEvent> streamChat({required String sessionId, required String message}) {
    return events;
  }
}

class FixedSessionManager extends SessionManager {
  FixedSessionManager(this.id);

  final String id;

  @override
  String build() => id;
}

void main() {
  test('sendMessage exposes tool activity and final streamed content', () async {
    final stream = Stream<SSEChatEvent>.fromIterable(const [
      SSEChatEvent(
        type: SSEChatEventType.messageStarted,
        sessionId: 'session-1',
        messageId: 'message-1',
        sequence: 1,
        payload: {},
      ),
      SSEChatEvent(
        type: SSEChatEventType.toolStarted,
        sessionId: 'session-1',
        messageId: 'message-1',
        sequence: 2,
        payload: {'name': 'search_notes', 'label': 'Buscando notas'},
      ),
      SSEChatEvent(
        type: SSEChatEventType.contentDelta,
        sessionId: 'session-1',
        messageId: 'message-1',
        sequence: 3,
        payload: {'delta': 'Achei uma nota.'},
      ),
      SSEChatEvent(
        type: SSEChatEventType.messageFinished,
        sessionId: 'session-1',
        messageId: 'message-1',
        sequence: 4,
        payload: {'content': 'Achei uma nota.'},
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        sessionManagerProvider.overrideWith(() => FixedSessionManager('session-1')),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        chatSSEProvider.overrideWith((ref) => FakeChatSSE(stream)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatControllerProvider.notifier).sendMessage('procure');
    await Future<void>.delayed(Duration.zero);

    final state = container.read(chatControllerProvider).value!;
    expect(state.isStreaming, isFalse);
    expect(state.activeToolLabel, isNull);
    expect(state.messages.last.content, 'Achei uma nota.');
  });
}
```

- [ ] **Step 2: Run controller test and confirm failure**

Run:

```powershell
flutter test test/features/agent/presentation/controllers/chat_controller_test.dart
```

Expected: FAIL because `chatSSEProvider`, `activeToolLabel`, and typed event handling do not exist.

- [ ] **Step 3: Replace `ChatState` typedef**

In `chat_controller.dart`, change `ChatState` to include explicit transient state:

```dart
typedef ChatState = ({
  List<MessageModel> messages,
  bool isStreaming,
  String? activeToolLabel,
  String? errorMessage,
  String? retryMessage,
});
```

Add an initial helper:

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

- [ ] **Step 4: Add injectable SSE provider**

In `chat_sse.dart`, add:

```dart
final chatSSEProvider = Provider.autoDispose<ChatSSE>((ref) {
  return ChatSSE(apiClient: ref.watch(apiClientProvider));
});
```

Add the missing imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
```

- [ ] **Step 5: Update controller stream handling**

In `sendMessage`, replace string-based event handling with typed switches:

```dart
final sse = ref.read(chatSSEProvider);
final messagesWithoutAssistant = [...currentMessages, pending];
final buffer = StringBuffer();

_sseSub = sse.streamChat(sessionId: sessionId, message: trimmed).listen(
  (event) {
    switch (event.type) {
      case SSEChatEventType.messageStarted:
        state = AsyncValue.data(chatState(
          messages: [...messagesWithoutAssistant, initialAssistant],
          isStreaming: true,
          retryMessage: trimmed,
        ));
      case SSEChatEventType.toolStarted:
        state = AsyncValue.data(chatState(
          messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
          isStreaming: true,
          activeToolLabel: event.toolLabel ?? 'Executando ação',
          retryMessage: trimmed,
        ));
      case SSEChatEventType.toolFinished:
      case SSEChatEventType.toolFailed:
        state = AsyncValue.data(chatState(
          messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
          isStreaming: true,
          activeToolLabel: null,
          retryMessage: trimmed,
        ));
      case SSEChatEventType.contentDelta:
        final delta = event.delta;
        if (delta != null) {
          buffer.write(delta);
        }
        state = AsyncValue.data(chatState(
          messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
          isStreaming: true,
          retryMessage: trimmed,
        ));
      case SSEChatEventType.messageFinished:
        final content = event.finalContent ?? buffer.toString();
        state = AsyncValue.data(chatState(
          messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: content)],
          isStreaming: false,
          retryMessage: trimmed,
        ));
      case SSEChatEventType.error:
        _setRecoverableError(event.errorMessage ?? 'Ocorreu um erro no stream', trimmed);
      case SSEChatEventType.unknown:
        break;
    }
  },
  onError: (Object e, StackTrace st) {
    _setRecoverableError(e is ApiException ? e.message : e.toString(), trimmed, st);
  },
  onDone: () {
    final current = state.valueOrNull;
    if (current == null || !current.isStreaming) return;
    state = AsyncValue.data(chatState(
      messages: [...messagesWithoutAssistant, initialAssistant.copyWith(content: buffer.toString())],
      isStreaming: false,
      retryMessage: trimmed,
    ));
  },
);
```

Add helper methods:

```dart
void _setRecoverableError(String message, String retryMessage, [StackTrace? st]) {
  final current = state.valueOrNull;
  if (current == null) {
    state = AsyncValue.error(message, st ?? StackTrace.current);
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

- [ ] **Step 6: Remove invalid internal Riverpod ignore**

Delete this line from `chat_controller.dart`:

```dart
// ignore_for_file: invalid_use_of_internal_member
```

Use `state.valueOrNull` or `state.hasValue` instead of `state.value`.

- [ ] **Step 7: Run controller tests and analyzer**

Run:

```powershell
flutter test test/features/agent/presentation/controllers/chat_controller_test.dart
dart analyze lib/features/agent/presentation/controllers/chat_controller.dart lib/features/agent/data/chat_sse.dart
```

Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit controller refactor**

Run:

```powershell
git add lib/features/agent/presentation/controllers/chat_controller.dart lib/features/agent/data/chat_sse.dart test/features/agent/presentation/controllers/chat_controller_test.dart
git commit -m "feat(agent): model chat stream state explicitly"
```

Expected: commit succeeds.

---

### Task 5: Render Tool Activity, Error, Retry, Cancel, And Empty Suggestions

**Files:**
- Modify: `lib/features/agent/presentation/widgets/agent_chat_view.dart`
- Modify: `lib/features/agent/presentation/chat_screen.dart`
- Modify: `test/features/agent/presentation/widgets/agent_chat_view_test.dart`
- Modify: `test/features/agent/presentation/chat_screen_test.dart`

- [ ] **Step 1: Add failing widget tests**

Append tests to `test/features/agent/presentation/widgets/agent_chat_view_test.dart`:

```dart
testWidgets('shows tool activity while streaming', (tester) async {
  await tester.pumpWidget(
    wrap(
      AgentChatView(
        messages: const [],
        loaded: true,
        streaming: true,
        activeToolLabel: 'Buscando notas',
        errorMessage: null,
        onRetry: null,
        onCancel: () {},
        onSend: (_) {},
      ),
    ),
  );
  await tester.pump();

  expect(find.text('Buscando notas'), findsOneWidget);
  expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
});

testWidgets('shows inline error with retry action', (tester) async {
  var retried = false;
  await tester.pumpWidget(
    wrap(
      AgentChatView(
        messages: const [],
        loaded: true,
        streaming: false,
        activeToolLabel: null,
        errorMessage: 'Falha no stream',
        onRetry: () => retried = true,
        onCancel: null,
        onSend: (_) {},
      ),
    ),
  );
  await tester.pump();

  expect(find.text('Falha no stream'), findsOneWidget);
  await tester.tap(find.text('Tentar novamente'));
  await tester.pump();
  expect(retried, isTrue);
});
```

- [ ] **Step 2: Run widget tests and confirm failure**

Run:

```powershell
flutter test test/features/agent/presentation/widgets/agent_chat_view_test.dart
```

Expected: FAIL because `AgentChatView` does not accept `activeToolLabel`, `errorMessage`, `onRetry`, or `onCancel`.

- [ ] **Step 3: Update `AgentChatView` constructor**

Add fields:

```dart
final String? activeToolLabel;
final String? errorMessage;
final VoidCallback? onRetry;
final VoidCallback? onCancel;
```

Add them as required constructor parameters except callbacks can be nullable:

```dart
required this.activeToolLabel,
required this.errorMessage,
this.onRetry,
this.onCancel,
```

- [ ] **Step 4: Add compact status overlay above composer**

In `AgentChatView.build`, wrap `flyer_ui.Chat` in a `Column`:

```dart
return Column(
  children: [
    Expanded(
      child: flyer_ui.Chat(
        currentUserId: agentChatCurrentUserId,
        resolveUser: resolveAgentChatUser,
        chatController: _chatController,
        theme: flyer.ChatTheme.fromThemeData(Theme.of(context)),
        builders: flyer.Builders(
          emptyChatListBuilder: (_) => _EmptyAgentChat(onSend: widget.onSend),
          customMessageBuilder: _buildCustomMessage,
          composerBuilder: (_) => ChatInput(
            enabled: !widget.streaming,
            onSend: widget.onSend,
          ),
        ),
        onMessageSend: widget.streaming ? null : widget.onSend,
      ),
    ),
    _AgentChatStatusBar(
      activeToolLabel: widget.activeToolLabel,
      errorMessage: widget.errorMessage,
      onRetry: widget.onRetry,
      onCancel: widget.streaming ? widget.onCancel : null,
    ),
  ],
);
```

Add `_AgentChatStatusBar` in the same file:

```dart
class _AgentChatStatusBar extends StatelessWidget {
  const _AgentChatStatusBar({
    required this.activeToolLabel,
    required this.errorMessage,
    required this.onRetry,
    required this.onCancel,
  });

  final String? activeToolLabel;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (activeToolLabel == null && errorMessage == null && onCancel == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (activeToolLabel != null) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(activeToolLabel!)),
            ] else if (errorMessage != null) ...[
              Icon(Icons.error_outline, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(errorMessage!)),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
            ] else
              const Spacer(),
            if (onCancel != null)
              IconButton(
                tooltip: 'Cancelar resposta',
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
          ],
        ),
      ),
    );
  }
}
```

Add `_EmptyAgentChat`:

```dart
class _EmptyAgentChat extends StatelessWidget {
  const _EmptyAgentChat({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    const prompts = [
      'Resuma minhas notas recentes',
      'Quais tarefas vencem hoje?',
      'Organize meu inbox',
    ];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'Comece uma conversa',
            subtitle: 'Pergunte algo ao agent e a resposta aparecerá aqui.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final prompt in prompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => onSend(prompt),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Wire new state in `ChatScreen`**

Update `AgentChatView` call:

```dart
AgentChatView(
  messages: messages,
  loaded: isLoaded,
  streaming: isStreaming,
  activeToolLabel: state?.activeToolLabel,
  errorMessage: state?.errorMessage,
  onRetry: state?.retryMessage == null
      ? null
      : () => ref.read(chatControllerProvider.notifier).retryLastMessage(),
  onCancel: isStreaming
      ? () => ref.read(chatControllerProvider.notifier).cancelStreaming()
      : null,
  onSend: (text) => ref.read(chatControllerProvider.notifier).sendMessage(text),
)
```

- [ ] **Step 6: Update existing `AgentChatView` test constructors**

Every existing test instantiation must pass:

```dart
activeToolLabel: null,
errorMessage: null,
onRetry: null,
onCancel: null,
```

- [ ] **Step 7: Run focused presentation tests**

Run:

```powershell
flutter test test/features/agent/presentation
dart analyze lib/features/agent/presentation test/features/agent/presentation
```

Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit UI state rendering**

Run:

```powershell
git add lib/features/agent/presentation test/features/agent/presentation
git commit -m "feat(agent): show chat tool activity and recovery actions"
```

Expected: commit succeeds.

---

### Task 6: Add Tool Risk Metadata And Confirmation Event

**Files:**
- Modify: `backend/internal/agent/tools/registry.go`
- Modify: `backend/internal/agent/events.go`
- Modify: `backend/internal/agent/events_test.go`

- [ ] **Step 1: Write failing risk metadata test**

Add to `backend/internal/agent/events_test.go` or create `backend/internal/agent/tools/registry_test.go`:

```go
package tools

import "testing"

func TestToolRegistryRiskDefaults(t *testing.T) {
	registry := &ToolRegistry{tools: map[string]ToolExecutor{}}

	cases := map[string]ToolRisk{
		"search_notes":             ToolRiskRead,
		"add_note":                 ToolRiskLowWrite,
		"update_note":              ToolRiskSensitiveWrite,
		"delete_memory":            ToolRiskSensitiveWrite,
		"apply_inbox_organization": ToolRiskSensitiveWrite,
	}

	for name, want := range cases {
		if got := registry.Risk(name); got != want {
			t.Fatalf("%s risk: want %s, got %s", name, want, got)
		}
	}
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```powershell
go test ./internal/agent/tools -run TestToolRegistryRiskDefaults
```

Expected: FAIL because `ToolRisk` and `Risk` do not exist.

- [ ] **Step 3: Add risk enum and lookup**

In `backend/internal/agent/tools/registry.go`:

```go
type ToolRisk string

const (
	ToolRiskRead           ToolRisk = "read"
	ToolRiskLowWrite       ToolRisk = "low_write"
	ToolRiskSensitiveWrite ToolRisk = "sensitive_write"
)

func (tr *ToolRegistry) Risk(toolName string) ToolRisk {
	switch toolName {
	case "search_notes", "get_note", "get_notes", "get_open_tasks", "get_today_tasks", "list_memories", "get_soul", "list_routines", "get_vault_context":
		return ToolRiskRead
	case "add_note", "add_task", "save_memory", "append_to_inbox":
		return ToolRiskLowWrite
	case "update_note", "delete_memory", "update_soul", "apply_inbox_organization", "set_daily_brief_schedule", "set_weekly_brief_schedule", "update_task", "complete_task":
		return ToolRiskSensitiveWrite
	default:
		return ToolRiskSensitiveWrite
	}
}
```

- [ ] **Step 4: Add confirmation event type**

In `backend/internal/agent/events.go`, add:

```go
EventConfirmationRequired EventType = "confirmation_required"
```

Add payload:

```go
type ConfirmationRequiredPayload struct {
	ToolName string `json:"tool_name"`
	Label    string `json:"label"`
	ArgsJSON string `json:"args_json"`
}
```

Update frontend parser later only when the implementation starts confirmation UI. In this task, the backend can expose the event type without routing it yet.

- [ ] **Step 5: Run focused backend tests**

Run:

```powershell
go test ./internal/agent/... ./internal/agent/tools/...
```

Expected: PASS.

- [ ] **Step 6: Commit risk metadata**

Run:

```powershell
git add backend/internal/agent/events.go backend/internal/agent/events_test.go backend/internal/agent/tools/registry.go backend/internal/agent/tools/registry_test.go
git commit -m "feat(agent): classify tool execution risk"
```

Expected: commit succeeds.

---

### Task 7: Structure Agent Prompt Context

**Files:**
- Modify: `backend/internal/agent/context.go`
- Modify: `backend/internal/agent/context_test.go`

- [ ] **Step 1: Add failing context section test**

In `backend/internal/agent/context_test.go`, add assertions to `TestContextBuilder_Build`:

```go
requiredSections := []string{
	"SYSTEM RULES:",
	"TOOL RULES:",
	"SOUL:",
	"CURRENT DATE & TIME:",
	"TODAY/OVERDUE TASKS:",
	"RECENT NOTES",
	"SEMANTIC SEARCH RESULTS:",
	"RELATED NOTES:",
	"RELEVANT MEMORIES:",
}
for _, section := range requiredSections {
	if !strings.Contains(result, section) {
		t.Fatalf("expected context to contain %q, got:\n%s", section, result)
	}
}
```

Add `strings` to imports if needed.

- [ ] **Step 2: Run context test and confirm failure**

Run:

```powershell
go test ./internal/agent -run TestContextBuilder_Build
```

Expected: FAIL because `SYSTEM RULES:` and `TOOL RULES:` are not present yet.

- [ ] **Step 3: Add structured prompt sections**

In `backend/internal/agent/context.go`, before `SOUL`, write:

```go
b.WriteString(`SYSTEM RULES:
- Answer in the user's language.
- Be concise and explicit about what changed.
- Admit when the available context is insufficient.

TOOL RULES:
- Use read tools when the current context is insufficient.
- Do not expose raw tool JSON or internal tool names to the user.
- Summarize successful writes in the final answer.
- Ask for confirmation before sensitive writes.

`)
```

Keep the existing `SOUL`, date/time, tasks, notes, semantic results, related notes, and memories sections.

Replace the final appended tool instruction with:

```go
b.WriteString("\nUse tools only when they directly help answer or complete the user's request.")
```

- [ ] **Step 4: Run context tests**

Run:

```powershell
go test ./internal/agent -run TestContextBuilder_Build
```

Expected: PASS.

- [ ] **Step 5: Commit prompt structure**

Run:

```powershell
git add backend/internal/agent/context.go backend/internal/agent/context_test.go
git commit -m "feat(agent): structure chat context rules"
```

Expected: commit succeeds.

---

### Task 8: Final Verification And Documentation

**Files:**
- Create: `task.md`
- Modify: `implementation_plan.md` if execution status changes

- [ ] **Step 1: Create execution tracker**

Create `task.md` when implementation starts:

```markdown
# Agent Chat Review Tasks

- [ ] Backend stream event contract
- [ ] Backend normalized stream emission
- [ ] Flutter typed stream parser
- [ ] Chat controller explicit state
- [ ] Chat UX status, retry, and cancel
- [ ] Tool risk metadata
- [ ] Structured agent prompt/context
- [ ] Final verification
```

- [ ] **Step 2: Run backend verification**

Run:

```powershell
go test ./internal/agent/... ./internal/agent/tools/...
```

Expected: PASS.

- [ ] **Step 3: Run Flutter verification**

Run:

```powershell
flutter test test/features/agent
dart analyze lib/features/agent test/features/agent
```

Expected: PASS and no analyzer issues.

- [ ] **Step 4: Run broader smoke verification**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
go test ./...
```

Expected: PASS. If `go test ./...` fails because integration-only packages need environment variables, record the failing package and keep the focused backend verification as the owned signal.

- [ ] **Step 5: Manual smoke test**

Run the Flutter app and verify:

```text
1. Chat opens from the existing route/FAB.
2. Empty chat shows prompt suggestions.
3. Sending a message creates an optimistic user message.
4. Assistant response streams into one assistant message.
5. Tool activity appears as a compact human label.
6. Cancel stops the active response and re-enables input.
7. Stream error preserves partial text and shows retry.
8. New conversation still rotates the session and reloads empty history.
```

- [ ] **Step 6: Commit tracker and final docs**

Run:

```powershell
git add task.md implementation_plan.md
git commit -m "docs(agent): track chat review implementation"
```

Expected: commit succeeds if these files changed during execution.

---

## Self-Review

- Spec coverage: Tasks cover normalized SSE events, explicit Flutter state, readable tool activity, retry/cancel/error UX, tool risk metadata, prompt/context structure, and focused backend/frontend tests.
- Scope check: The plan is large but still one connected vertical slice: agent chat behavior. It avoids unrelated editor, sync, auth, routing, and notes UI work.
- Placeholder scan: No task uses open placeholder language. Each code-changing step includes concrete code or exact replacement snippets.
- Type consistency: Backend event type names match Flutter parser enum cases. `message_finished` replaces old `done`; `tool_started`/`tool_finished`/`tool_failed` replace old `tool_use`/`tool_result` in the new path.
- Risk note: The controller test fake may require small constructor/interface adjustment because `ChatSSE` currently requires `ApiClient`; the plan resolves that by introducing `chatSSEProvider` and overriding it in tests.
