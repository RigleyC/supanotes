# Agent And Chat Review Design

## Goal

Improve the SupaNotes agent and chat experience end to end without replacing the current Flutter and Go architecture.

The work should make the chat easier to trust, easier to understand, and easier to maintain:

- The user can tell when the agent is responding, searching, acting, failing, or waiting for confirmation.
- Sensitive actions do not happen silently.
- Streaming, errors, retry, and cancellation have explicit state.
- Backend and frontend communicate through a stable event contract.
- Agent context and tool rules are structured enough to test and evolve.

## Current Context

The Flutter chat lives under `lib/features/agent`:

- `presentation/controllers/chat_controller.dart` owns history loading, optimistic messages, SSE subscription, tool status text, and error handling.
- `data/chat_sse.dart` parses `POST /agent/chat/stream`.
- `data/chat_repository.dart` handles history and the older synchronous chat endpoint.
- `presentation/widgets/agent_chat_view.dart` renders through `flutter_chat_ui`.

The backend agent lives under `backend/internal/agent`:

- `handler.go` exposes `/agent/chat`, `/agent/chat/stream`, `/agent/messages`, and history deletion.
- `loop.go` persists turns, builds context, calls the LLM, executes tools, and emits SSE events.
- `context.go` builds the Soul, notes, task, memory, and semantic-search context.
- `tools/registry.go` registers read and write tools.

The current design works, but it makes the frontend infer too much from loosely shaped SSE data and pushes tool status into assistant message text.

## Assumptions

- Keep Flutter, Riverpod, `flutter_chat_ui`, Go, and the current backend package structure.
- Do not rewrite the agent loop as a separate orchestration engine in this pass.
- Improve product confidence and maintainability before chasing model-quality tuning alone.
- Preserve existing agent tools unless a tool needs risk classification or confirmation metadata.
- Use manual Riverpod providers only, following `RIVERPOD.md`.

## Non-Goals

- No new LLM provider migration.
- No full replacement of `flutter_chat_ui`.
- No large redesign of notes, tasks, memories, routines, or sync.
- No speculative multi-agent system.
- No unrelated cleanup in editor, auth, routing, or note list code.

## Event Contract

Create a stable SSE event contract between backend and Flutter.

Each streamed event should include:

- `session_id`
- `message_id`
- `sequence`
- `type`
- `payload`

Required event types:

- `message_started`
- `content_delta`
- `tool_started`
- `tool_finished`
- `tool_failed`
- `message_finished`
- `error`

The backend should emit one shape for all events instead of special-casing `content_delta` and `done`. The frontend should parse typed events directly and should not infer tool activity from free-form strings.

`message_id` should identify the assistant response being streamed. `sequence` should make ordering testable and protect the client from duplicate or out-of-order updates.

## Flutter State Model

Refactor `ChatController` into explicit chat state instead of embedding transient status in message content.

The state should represent:

- Loaded messages.
- Pending optimistic user message.
- Active streaming assistant message.
- Active tool activity.
- Recoverable error.
- Whether sending, streaming, retrying, or cancelling is available.

The controller should not need `ignore_for_file: invalid_use_of_internal_member`. It should avoid `state.value!` and should preserve previous data when reporting errors.

Typed parsing belongs in the data/domain layer. Rendering decisions belong in widgets. The controller should translate stream events into state transitions.

## Chat UX

The chat should show progress without becoming a technical log.

During normal responses:

- Render assistant text as it streams.
- Show a subtle response state while the first delta is pending.

During tool activity:

- Show compact human labels such as `Buscando notas`, `Atualizando tarefa`, or `Salvando memória`.
- Do not show raw tool names or JSON to the user.
- Clear the activity when the tool finishes or fails.

For errors:

- Keep any partial assistant response visible.
- Show an inline recoverable error state.
- Offer retry when the user can retry the last message.

For controls:

- Allow cancelling an active response.
- Keep starting a new session explicit.
- Keep the empty state useful with prompt suggestions.

## Tool Risk Policy

Classify agent tools by risk.

Read-safe tools can run without confirmation:

- Search notes.
- Get notes.
- Get tasks.
- Get memories.
- Get vault context.
- Get Soul.
- List routines.

Low-risk reversible writes may execute directly but must report what changed:

- Create note.
- Add task.
- Save memory.
- Append to inbox.

Sensitive writes require preview or confirmation before applying:

- Edit an existing note.
- Delete a memory.
- Update Soul.
- Apply inbox organization.
- Change routine schedules.
- Any destructive or broad update.

The first implementation can express this policy as metadata on tools and enforce it in the agent loop or handler layer. The UI should receive a confirmation-needed event instead of the backend silently applying sensitive changes.

## Agent Prompt And Context

Keep `ContextBuilder`, but structure its output more deliberately:

- System rules.
- Tool-use rules.
- Soul/personality.
- Current date and time.
- Recent tasks.
- Recent notes.
- Semantic notes.
- Related notes.
- Relevant memories.

The prompt should tell the model:

- Use read tools when context is insufficient.
- Ask for confirmation before sensitive writes.
- Say what changed after writing data.
- Admit missing context instead of inventing.
- Keep internal tool details out of the user-facing answer.

Tool traces should be summarized in the final response when data changes, for example: `Criei a nota X`, `Atualizei 2 tarefas`, or `Não encontrei notas sobre Y`.

## Backend Persistence

Persist user messages and final assistant messages as normal chat history.

Do not present raw tool messages as ordinary chat messages. Tool traces can be stored separately or compressed into metadata if needed for debugging and future context. If the existing `messages` table remains the only storage, tool messages should be hidden from the user-facing history and summarized for the model carefully.

The synchronous `/agent/chat` endpoint can be kept temporarily as fallback, but the streaming endpoint should become the primary path. A later cleanup can remove `/agent/chat` if no callers remain.

## Testing Strategy

Add focused tests by layer.

Backend:

- SSE event shape and event ordering.
- Loop behavior for content-only responses.
- Loop behavior for tool start, finish, failure, and final answer.
- Tool risk classification.
- Confirmation-required behavior for sensitive tools.
- ContextBuilder output sections.

Flutter:

- SSE parser handles every event type.
- ChatController state transitions for load, stream, tool activity, error, retry, cancel, and completion.
- Widget rendering for empty state, streaming text, tool activity, inline error, retry, and disabled composer.

Avoid tests that depend on a live LLM. Use stubs and fixtures.

## Rollout

Implement in small phases:

1. Define backend and Flutter event types, then add parser and event tests.
2. Update backend streaming to emit the normalized contract.
3. Refactor Flutter controller state around typed events.
4. Add visible tool activity and error/retry/cancel UX.
5. Add tool risk metadata and confirmation handling for sensitive writes.
6. Restructure prompt/context output and add fixture tests.
7. Decide whether to remove or keep `/agent/chat`.

Each phase should be independently testable and should avoid unrelated refactors.

## Success Criteria

- The user can see whether the agent is replying, searching, acting, waiting for confirmation, or failing.
- Partial responses survive stream errors.
- Retry and cancel behave predictably.
- Sensitive writes do not execute silently.
- Tool activity is readable without exposing internals.
- The frontend no longer relies on ad hoc status strings inside assistant content.
- Backend and frontend have tests around the stream contract.
- Existing chat history still loads correctly.
