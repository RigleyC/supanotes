# Chat Agent Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct backend and frontend chat agent issues: fix GetMessages query bug (recent messages order), remove context duplication in prompt, make inbox organization transactional, implement missing agent tools, and add frontend visual feedback during tool calls while preserving history on error.

**Architecture:** 
1. Fix GetMessages query to select the most recent messages using a SQL subquery.
2. Remove duplicate history text from the backend ContextBuilder system prompt.
3. Update notes.Service to accept pgxpool.Pool and execute ApplyOrganization in a database transaction using the WithQuerier pattern.
4. Define and register plan_inbox_organization and apply_inbox_organization in tools.go.
5. Parse tool_use and tool_result SSE events on the frontend and render a visual "thinking" indicator during execution.
6. Use Riverpod's copyWithPrevious to preserve message history on streaming error states, and remove unused files.

**Tech Stack:** Go (Echo + pgx + sqlc), Flutter (Riverpod 3.x, flyer/flutter_chat_ui).

---

## Proposed Changes

### Database Layer

#### [MODIFY] [agent.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/agent.sql)
Update GetMessages query to fetch the latest messages using a subquery and sort them chronologically (ascending).

---

### Backend Components

#### [MODIFY] [context.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/context.go)
Remove recent messages history formatting from the system prompt block to avoid duplication.

#### [MODIFY] [repository.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/repository.go)
Add `WithQuerier(q sqlcgen.Querier) Repository` method signature and implementation.

#### [MODIFY] [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/service.go)
Modify `notes.NewService` to accept `pool *pgxpool.Pool` and update `ApplyOrganization` to wrap its queries within a pgx transaction.

#### [MODIFY] [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go)
Update `NewToolRegistry` to accept `llmFactory llm.Factory`, and add `plan_inbox_organization` and `apply_inbox_organization` tool executors.

#### [MODIFY] [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go)
Inject the pgxpool to `notes.NewService` and `llmFactory` to `agent.NewToolRegistry` calls.

---

### Frontend Components

#### [MODIFY] [sse_chat_event.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/domain/sse_chat_event.dart)
Resurrect and refine `SSEChatEvent` model to support parsing delta, done, tool_use, tool_result, and error fields.

#### [MODIFY] [chat_sse.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/data/chat_sse.dart)
Update `streamChat` to return a `Stream<SSEChatEvent>` instead of `Stream<String>`.

#### [MODIFY] [chat_controller.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/presentation/controllers/chat_controller.dart)
Update controller to listen to `SSEChatEvent`, display temporary tool execution status texts, and preserve message history on streaming error using `copyWithPrevious`.

#### [DELETE] [agent_repository.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/data/agent_repository.dart)
Delete the unused repository file.

---

## Tasks

### Task 1: Fix GetMessages SQL Query and Compile SQLC

**Files:**
- Modify: `backend/db/queries/agent.sql`

- [ ] **Step 1: Rewrite GetMessages in `agent.sql`**
  Modify [agent.sql](file:///c:/Users/rigleyc/projects/supanotes/backend/db/queries/agent.sql) to select the latest records using a subquery and sort them ascending:
  ```sql
  -- name: GetMessages :many
  SELECT * FROM (
    SELECT * FROM messages
    WHERE user_id = $1 AND session_id = $2
    ORDER BY created_at DESC
    LIMIT $3 OFFSET $4
  ) sub
  ORDER BY created_at ASC;
  ```

- [ ] **Step 2: Compile SQLC queries**
  From the `backend` directory, run sqlc generation to update the Go database files:
  Run:
  ```powershell
  cd backend
  sqlc generate
  ```
  Expected: sqlc compiles successfully without errors, updating `backend/internal/db/sqlcgen/agent.sql.go`.

- [ ] **Step 3: Run backend agent tests**
  Verify that the changes do not break existing queries and tests:
  Run:
  ```powershell
  go test ./internal/agent/...
  ```
  Expected: PASS

- [ ] **Step 4: Commit SQL and generated files**
  Run:
  ```powershell
  git add db/queries/agent.sql internal/db/sqlcgen/agent.sql.go
  git commit -m "fix(db): retrieve recent messages chronologically in GetMessages query"
  ```

---

### Task 2: Remove Duplicated History in Context Builder

**Files:**
- Modify: `backend/internal/agent/context.go`

- [ ] **Step 1: Remove messages history loop from `Build`**
  Open [context.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/context.go#L151-L156) and remove the code that appends recent messages to the system prompt builder:
  ```go
  // Remove this block:
  for _, m := range recentMsgs {
      b.WriteString(fmt.Sprintf("[%s]: %s\n", m.Role, m.Content))
  }
  ```
  Also adjust `truncate` call to only cover the `soul.Personality` and `now` timestamp.

- [ ] **Step 2: Run backend tests to verify ContextBuilder**
  Run:
  ```powershell
  go test ./internal/agent/...
  ```
  Expected: PASS

- [ ] **Step 3: Commit context changes**
  Run:
  ```powershell
  git add internal/agent/context.go
  git commit -m "fix(agent): remove duplicate conversation history from system prompt"
  ```

---

### Task 3: Make ApplyOrganization Database Transactional

**Files:**
- Modify: `backend/internal/notes/repository.go`
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Add WithQuerier to Repository interface**
  Open [repository.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/repository.go) and update the Repository interface and struct implementation:
  ```go
  type Repository interface {
      // ... existing methods
      WithQuerier(q sqlcgen.Querier) Repository
  }

  // ...
  func (r *repository) WithQuerier(q sqlcgen.Querier) Repository {
      return &repository{q: q}
  }
  ```

- [ ] **Step 2: Update notes.Service to accept pgxpool.Pool**
  Open [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/service.go) and update the Service definition and constructor:
  ```go
  type Service struct {
      repo Repository
      pool *pgxpool.Pool
  }

  func NewService(repo Repository, pool *pgxpool.Pool) *Service {
      return &Service{repo: repo, pool: pool}
  }
  ```

- [ ] **Step 3: Update ApplyOrganization to use a database transaction**
  In [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/notes/service.go), rewrite `ApplyOrganization` to wrap its writes in a transaction:
  ```go
  func (s *Service) ApplyOrganization(ctx context.Context, userID pgtype.UUID, items []PlanOrganizationItem) error {
      r := s.repo
      var tx pgx.Tx
      if s.pool != nil {
          var err error
          tx, err = s.pool.Begin(ctx)
          if err != nil {
              return err
          }
          defer tx.Rollback(ctx)
          r = s.repo.WithQuerier(sqlcgen.New(tx))
      }

      inbox, err := r.GetInboxNote(ctx, userID)
      if err != nil {
          return err
      }

      noteIDStr := uid.UUIDToString(inbox.ID)
      lines := strings.Split(inbox.Content, "\n\n")

      outgoing := make(map[string]PlanOrganizationItem, len(items))
      for _, item := range items {
          if item.Accepted {
              outgoing[item.ItemID] = item
          }
      }

      var keptLines []string
      for i, line := range lines {
          trimmed := strings.TrimSpace(line)
          if trimmed == "" {
              continue
          }

          itemID := fmt.Sprintf("%s-%d", noteIDStr, i)
          reqItem, isOutgoing := outgoing[itemID]

          if !isOutgoing {
              keptLines = append(keptLines, trimmed)
              continue
          }

          switch reqItem.DestinationType {
          case DestNewNote:
              titleText := pgtype.Text{}
              if reqItem.DestinationTitle != nil {
                  titleText = pgtype.Text{String: *reqItem.DestinationTitle, Valid: true}
              }
              if _, err := r.CreateNote(ctx, sqlcgen.CreateNoteParams{
                  UserID:          userID,
                  Title:           titleText,
                  Content:         trimmed,
                  IsInbox:         false,
                  Favorite:        false,
                  Archived:        false,
                  EmbeddingStatus: "pending",
              }); err != nil {
                  return fmt.Errorf("create note: %w", err)
              }
          case DestExistingNote:
              if reqItem.DestinationNoteID != nil {
                  noteID, err := uid.UUIDFromString(*reqItem.DestinationNoteID)
                  if err == nil {
                      if _, err := r.GetNoteByID(ctx, noteID, userID); err != nil {
                          return fmt.Errorf("destination note not found: %w", err)
                      }
                      if _, err := r.AppendToNoteContent(ctx, sqlcgen.AppendToNoteContentParams{
                          ID:      noteID,
                          UserID:  userID,
                          Content: trimmed,
                      }); err != nil {
                          return fmt.Errorf("append to note: %w", err)
                      }
                  } else {
                      return fmt.Errorf("invalid destination note id: %w", err)
                  }
              }
          case DestKeep:
              keptLines = append(keptLines, trimmed)
          }
      }

      newContent := strings.Join(keptLines, "\n\n")
      if _, err = r.SetInboxContent(ctx, sqlcgen.SetInboxContentParams{
          ID:      inbox.ID,
          UserID:  userID,
          Content: newContent,
      }); err != nil {
          return err
      }

      if tx != nil {
          return tx.Commit(ctx)
      }
      return nil
  }
  ```

- [ ] **Step 4: Update service instantiation in main.go**
  Open [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go#L183) and pass the pool to `notes.NewService`:
  ```go
  notesSvc := notes.NewService(notesRepo, pool)
  ```
  Also update any test setups in `service_test.go` or other test files by passing `nil` for the pool parameter:
  ```go
  // Example in backend/internal/agent/tools_test.go:431
  return notes.NewService(&mockNotesRepo{q: q}, nil)
  ```

- [ ] **Step 5: Run tests and verify backend compilation**
  Run:
  ```powershell
  go test ./internal/notes/...
  go test ./internal/agent/...
  ```
  Expected: PASS

- [ ] **Step 6: Commit transactional changes**
  Run:
  ```powershell
  git add cmd/server/main.go internal/notes/repository.go internal/notes/service.go internal/agent/tools_test.go internal/notes/service_test.go
  git commit -m "feat(notes): make inbox organization plan application transactional"
  ```

---

### Task 4: Add plan_inbox_organization and apply_inbox_organization Agent Tools

**Files:**
- Modify: `backend/internal/agent/tools.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Update NewToolRegistry constructor and tools.go imports**
  Modify [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go) to import the `notes` package (for `notes.PlanOrganizationItem` or unmarshaling structs) and update `NewToolRegistry` to receive `llmFact llm.Factory`:
  ```go
  type ToolRegistry struct {
      tools map[string]ToolExecutor
  }

  func NewToolRegistry(
      q sqlcgen.Querier, 
      notesSvc *notes.Service, 
      tasksSvc *tasks.Service, 
      memoriesSvc *memories.Service, 
      routinesSvc *routines.Service, 
      soulSvc *soul.Service, 
      embedCL *llm.EmbeddingClient,
      llmFact llm.Factory,
  ) *ToolRegistry {
      // Add tools:
      // &PlanInboxOrganizationTool{notesSvc: notesSvc, llmClient: llmFact.For(llm.TaskTypeInboxOrganize)},
      // &ApplyInboxOrganizationTool{notesSvc: notesSvc},
  ```

- [ ] **Step 2: Implement PlanInboxOrganizationTool**
  Add the following structs and methods to [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go):
  ```go
  // --- PlanInboxOrganizationTool ---
  type PlanInboxOrganizationTool struct {
      notesSvc  *notes.Service
      llmClient llm.Client
  }

  func (t *PlanInboxOrganizationTool) Name() string { return "plan_inbox_organization" }
  func (t *PlanInboxOrganizationTool) Description() string {
      return "Analyze the inbox content and propose how to organize snippets into notes, without editing anything"
  }
  func (t *PlanInboxOrganizationTool) SchemaJSON() string {
      return `{"type":"object","properties":{}}`
  }
  func (t *PlanInboxOrganizationTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
      note, err := t.notesSvc.GetInboxNote(ctx, userID)
      if err != nil {
          return "", err
      }

      systemPrompt := `Você é um organizador de notas. Analise o conteúdo do inbox abaixo e organize cada item.
  O inbox contém várias anotações separadas por linhas em branco. Para cada anotação, decida o destino:
  - "new_note": virar uma nova nota → forneça um título descritivo curto
  - "keep": permanecer no inbox
  Responda APENAS com um JSON array válido. Exemplo:
  [{"snippet": "primeira anotação", "destination": "new_note", "title": "Título Descritivo"},
   {"snippet": "segunda anotação", "destination": "keep"}]`

      resp, err := t.llmClient.Complete(ctx, llm.Request{
          System: systemPrompt,
          Messages: []llm.Message{
              {Role: llm.RoleUser, Content: "Aqui está meu inbox:\n\n" + note.Content},
          },
          MaxTokens:   2000,
          Temperature: 0.3,
      })
      if err != nil {
          return "", err
      }
      return resp.Content, nil
  }
  ```

- [ ] **Step 3: Implement ApplyInboxOrganizationTool**
  Add `ApplyInboxOrganizationTool` to [tools.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/agent/tools.go):
  ```go
  // --- ApplyInboxOrganizationTool ---
  type ApplyInboxOrganizationTool struct {
      notesSvc *notes.Service
  }

  func (t *ApplyInboxOrganizationTool) Name() string { return "apply_inbox_organization" }
  func (t *ApplyInboxOrganizationTool) Description() string {
      return "Apply a confirmed inbox organization plan and remove organized items from the inbox"
  }
  func (t *ApplyInboxOrganizationTool) SchemaJSON() string {
      return `{"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"item_id":{"type":"string"},"destination_type":{"type":"string"},"destination_note_id":{"type":"string"},"destination_title":{"type":"string"},"accepted":{"type":"boolean"}},"required":["item_id","destination_type","accepted"]}}},"required":["items"]}`
  }
  func (t *ApplyInboxOrganizationTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
      var args struct {
          Items []notes.PlanOrganizationItem `json:"items"`
      }
      if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
          return "", fmt.Errorf("parse args: %w", err)
      }
      if err := t.notesSvc.ApplyOrganization(ctx, userID, args.Items); err != nil {
          return "", err
      }
      return "Inbox organization plan applied successfully", nil
  }
  ```

- [ ] **Step 4: Update cmd/server/main.go instantiation**
  Open [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/server/main.go#L255) and pass `llmFactory` to `agent.NewToolRegistry`:
  ```go
  agentTools := agent.NewToolRegistry(queries, notesSvc, tasksSvc, memoriesSvc, routinesSvc, soulSvc, embeddingClient, llmFactory)
  ```
  Also update test stubs in `internal/agent/tools_test.go` or other tests where `NewToolRegistry` is called by passing a mocked or `nil` llm.Factory.

- [ ] **Step 5: Run tests and verify compile**
  Run:
  ```powershell
  go test ./internal/agent/...
  ```
  Expected: PASS

- [ ] **Step 6: Commit new agent tools**
  Run:
  ```powershell
  git add internal/agent/tools.go cmd/server/main.go internal/agent/tools_test.go
  git commit -m "feat(agent): register plan_inbox_organization and apply_inbox_organization tools"
  ```

---

### Task 5: Refine Frontend SSE Event Parsing and streamChat

**Files:**
- Modify: `lib/features/agent/domain/sse_chat_event.dart`
- Modify: `lib/features/agent/data/chat_sse.dart`

- [ ] **Step 1: Clean up and refine sse_chat_event.dart**
  Open [sse_chat_event.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/domain/sse_chat_event.dart) and update the class definition to support all wire format structures:
  ```dart
  class SSEChatEvent {
    final String type;
    final String? delta;
    final String? data;
    final bool? done;

    SSEChatEvent({
      required this.type,
      this.delta,
      this.data,
      this.done,
    });

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
      } else if (json.containsKey('error')) {
        return SSEChatEvent(
          type: 'error',
          data: json['error'] as String?,
        );
      }
      return SSEChatEvent(type: 'unknown');
    }
  }
  ```

- [ ] **Step 2: Update ChatSSE to yield SSEChatEvent**
  Open [chat_sse.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/data/chat_sse.dart) and update `streamChat` signature and body:
  ```dart
  import '../domain/sse_chat_event.dart'; // Add import

  class ChatSSE {
    // ...
    Stream<SSEChatEvent> streamChat({
      required String sessionId,
      required String message,
    }) {
      _cancelToken = CancelToken();
      final controller = StreamController<SSEChatEvent>();

      _api.postStream(
        '/agent/chat/stream',
        data: <String, dynamic>{
          'session_id': sessionId,
          'content': message,
        },
        options: Options(receiveTimeout: const Duration(minutes: 5)),
        cancelToken: _cancelToken,
      ).then((response) async {
        final body = response.data as ResponseBody;
        final lines = body.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          if (_cancelToken?.isCancelled ?? false) break;
          if (!line.startsWith('data: ')) continue;

          final jsonStr = line.substring(6);
          if (jsonStr.isEmpty) continue;

          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final event = SSEChatEvent.fromJson(data);
            
            if (event.type == 'error') {
              controller.addError(
                ApiException(message: event.data ?? 'Ocorreu um erro no stream'),
              );
              break;
            }
            
            controller.add(event);

            if (event.type == 'done') {
              break;
            }
          } catch (_) {
            // skip malformed lines
          }
        }
        await controller.close();
      }).catchError((Object e) {
        if (e is DioException && CancelToken.isCancel(e)) return;
        controller.addError(fromDioError(e as DioException));
        controller.close();
      });

      return controller.stream;
    }
  }
  ```

- [ ] **Step 3: Analyze and commit sse changes**
  Run:
  ```powershell
  rtk flutter pub get
  rtk dart analyze lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart
  ```
  Expected: `No issues found!`
  Commit:
  ```powershell
  rtk git add lib/features/agent/domain/sse_chat_event.dart lib/features/agent/data/chat_sse.dart
  rtk git commit -m "feat(agent): update chat SSE to stream rich tool calling events"
  ```

---

### Task 6: Implement Tool Calling Feedback in Controller & Preserve Error State

**Files:**
- Modify: `lib/features/agent/presentation/controllers/chat_controller.dart`
- Delete: `lib/features/agent/data/agent_repository.dart`

- [ ] **Step 1: Listen to tool calls and handle error state in ChatController**
  Modify [chat_controller.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/agent/presentation/controllers/chat_controller.dart)'s `sendMessage` to parse `SSEChatEvent` and keep previous messages on error using `copyWithPrevious`:
  ```dart
  import 'dart:convert'; // Add import if not present

  // ...
  Future<void> sendMessage(String content) async {
      final trimmed = content.trim();
      if (trimmed.isEmpty) return;

      final sessionId = ref.read(sessionManagerProvider);
      final currentMessages = state.value?.messages ?? [];

      final pending = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        sessionId: sessionId,
        role: MessageRole.user,
        content: trimmed,
        createdAt: DateTime.now(),
      );

      final assistantId = 'assistant-${DateTime.now().microsecondsSinceEpoch}';
      final initialAssistant = MessageModel(
        id: assistantId,
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: '',
        createdAt: DateTime.now(),
      );

      state = AsyncValue.data((
        messages: [...currentMessages, pending, initialAssistant],
        isStreaming: true,
      ));

      _sseSub?.cancel();
      final sse = ChatSSE(apiClient: ref.read(apiClientProvider));

      final messagesWithoutAssistant = [...currentMessages, pending];
      final buffer = StringBuffer();
      String currentToolStatus = '';

      _sseSub = sse.streamChat(
        sessionId: sessionId,
        message: trimmed,
      ).listen(
        (event) {
          if (event.type == 'content_delta' && event.delta != null) {
            buffer.write(event.delta);
            currentToolStatus = ''; // Clear tool status when text response starts
            final updatedAssistant = initialAssistant.copyWith(
              content: buffer.toString(),
            );
            state = AsyncValue.data((
              messages: [...messagesWithoutAssistant, updatedAssistant],
              isStreaming: true,
            ));
          } else if (event.type == 'tool_use' && event.data != null) {
            try {
              final toolCall = jsonDecode(event.data!) as Map<String, dynamic>;
              final toolName = toolCall['name'] as String? ?? 'processamento';
              
              currentToolStatus = '\n\n*(Pensando... executando ação: $toolName)*';
              final updatedAssistant = initialAssistant.copyWith(
                content: buffer.toString() + currentToolStatus,
              );
              state = AsyncValue.data((
                messages: [...messagesWithoutAssistant, updatedAssistant],
                isStreaming: true,
              ));
            } catch (_) {}
          } else if (event.type == 'tool_result') {
            currentToolStatus = '\n\n*(Pensando... processando resultado)*';
            final updatedAssistant = initialAssistant.copyWith(
              content: buffer.toString() + currentToolStatus,
            );
            state = AsyncValue.data((
              messages: [...messagesWithoutAssistant, updatedAssistant],
              isStreaming: true,
            ));
          } else if (event.type == 'done') {
            final current = state.value;
            if (current != null) {
              // Strip out any trailing thinking status on completion
              final finalAssistant = initialAssistant.copyWith(
                content: buffer.toString(),
              );
              state = AsyncValue.data((
                messages: [...messagesWithoutAssistant, finalAssistant],
                isStreaming: false,
              ));
            }
          }
        },
        onError: (Object e, StackTrace st) {
          final previousState = state;
          state = AsyncError<ChatState>(
            e is ApiException ? e.message : e.toString(),
            st,
          ).copyWithPrevious(previousState);
          // Set streaming status to false so the user can try sending another message
          if (state.hasValue) {
            state = AsyncValue.data((
              messages: state.value!.messages,
              isStreaming: false,
            ));
          }
        },
        onDone: () {
          final current = state.value;
          if (current != null) {
            // Strip out thinking status if stream ended normally
            final finalAssistant = initialAssistant.copyWith(
              content: buffer.toString(),
            );
            state = AsyncValue.data((
              messages: [...messagesWithoutAssistant, finalAssistant],
              isStreaming: false,
            ));
          }
        },
      );
  }
  ```

- [ ] **Step 2: Remove dead code files**
  Remove the unused `agent_repository.dart` from git:
  Run:
  ```powershell
  rtk git rm lib/features/agent/data/agent_repository.dart
  ```

- [ ] **Step 3: Analyze and verify frontend tests**
  Run code analysis and execute Flutter unit tests to verify no compilation errors:
  Run:
  ```powershell
  rtk dart analyze lib/features/agent
  rtk flutter test test/features/agent
  ```
  Expected: PASS

- [ ] **Step 4: Commit controller changes**
  Run:
  ```powershell
  git add lib/features/agent/presentation/controllers/chat_controller.dart
  git commit -m "feat(agent): display visual tool calls feedback and preserve history on error"
  ```
