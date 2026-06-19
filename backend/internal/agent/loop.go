package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"sync"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/agent/tools"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type Loop struct {
	repo    Repository
	llmFact llm.Factory
	ctxBldr *ContextBuilder
	tools   *ToolRegistry
}

func NewLoop(repo Repository, llmFact llm.Factory, ctxBldr *ContextBuilder, tools *ToolRegistry) *Loop {
	return &Loop{
		repo:    repo,
		llmFact: llmFact,
		ctxBldr: ctxBldr,
		tools:   tools,
	}
}

type SSEEvent struct {
	Type string
	Data string
}

func sendEvent(events chan<- SSEEvent, typ, data string) {
	if events != nil {
		events <- SSEEvent{Type: typ, Data: data}
	}
}

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

func (l *Loop) Chat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string) (<-chan string, error) {
	ch := make(chan string, 10)

	go func() {
		defer close(ch)

		events := make(chan SSEEvent, 20)
		var wg sync.WaitGroup
		wg.Add(1)
		go func() {
			defer wg.Done()
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
		}()

		_, err := l.doChat(ctx, userID, sessionIDStr, userMessage, events)
		if err != nil {
			slog.Error("chat failed", "error", err)
		}
		close(events)
		wg.Wait()
	}()

	return ch, nil
}

func (l *Loop) ResetSession(ctx context.Context, userID pgtype.UUID, sessionIDStr string) error {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return fmt.Errorf("invalid session id: %w", err)
	}
	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}
	return l.repo.DeleteSessionMessages(ctx, userID, sessionUUID)
}

func (l *Loop) ExecuteTool(ctx context.Context, userID pgtype.UUID, toolName, argsJSON string) (string, error) {
	return l.tools.Execute(ctx, userID, toolName, argsJSON)
}

func (l *Loop) ChatStream(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- SSEEvent) error {
	_, err := l.doChat(ctx, userID, sessionIDStr, userMessage, events)
	return err
}

func (l *Loop) doChat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- SSEEvent) (string, error) {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return "", fmt.Errorf("invalid session id: %w", err)
	}

	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}

	assistantMessageID := uuid.NewString()
	writer := NewStreamEventWriter(sessionIDStr, assistantMessageID)
	sendStreamEvent(events, writer.Event(
		EventMessageStarted,
		map[string]string{"role": string(llm.RoleAssistant)},
	))

	// 1. Save User Message
	_, err = l.repo.CreateMessage(ctx, userID, sessionUUID, string(llm.RoleUser), userMessage, nil, nil)
	if err != nil {
		return "", fmt.Errorf("save user msg: %w", err)
	}

	// 2. Build Tiered Context
	sysPrompt, err := l.ctxBldr.Build(ctx, userID, sessionUUID, userMessage)
	if err != nil {
		return "", fmt.Errorf("build context: %w", err)
	}

	// 3. Get LLM Client
	client := l.llmFact.For(llm.TaskTypeAgentic)
	toolDefs := l.tools.GetTools()

	messages, err := l.loadHistory(ctx, userID, sessionUUID)
	if err != nil {
		return "", fmt.Errorf("load history: %w", err)
	}

	finalContent := ""
	var lastToolResults []string

	// 4. Tool Calling Loop (max 5 iterations)
	for i := 0; i < 5; i++ {
		req := llm.Request{
			System:      sysPrompt,
			Messages:    messages,
			Tools:       toolDefs,
			MaxTokens:   4000,
			Temperature: 0.7,
		}

		res, err := client.Complete(ctx, req)
		if err != nil {
			if len(lastToolResults) > 0 {
				slog.Warn("llm call failed after tool execution; finishing with tool result", "error", err, "iteration", i)
				finalContent = strings.Join(lastToolResults, "\n")
				sendStreamEvent(events, writer.Event(
					EventMessageFinished,
					MessageFinishedPayload{Content: finalContent},
				))
				return finalContent, nil
			}
			return "", fmt.Errorf("llm call: %w", err)
		}
		if res.Content == "" && len(res.ToolCalls) == 0 {
			slog.Warn("llm returned empty agent response; retrying without tools", "iteration", i)
			fallbackReq := req
			fallbackReq.Tools = nil
			res, err = client.Complete(ctx, fallbackReq)
			if err != nil {
				return "", fmt.Errorf("llm fallback call: %w", err)
			}
			if res.Content == "" && len(res.ToolCalls) == 0 {
				if len(lastToolResults) > 0 {
					res.Content = strings.Join(lastToolResults, "\n")
					res.ToolCalls = nil
					slog.Warn("llm returned empty agent response; finishing with tool result", "iteration", i)
				} else {
					slog.Error("llm returned empty agent response", "iteration", i)
					return "", fmt.Errorf("llm returned empty response")
				}
			}
		}

		assistMsg := llm.Message{
			Role:      llm.RoleAssistant,
			Content:   res.Content,
			ToolCalls: res.ToolCalls,
		}
		messages = append(messages, assistMsg)

		if _, err := l.persistTurn(ctx, userID, sessionUUID, assistMsg); err != nil {
			return "", fmt.Errorf("save assistant msg: %w", err)
		}

		if res.Content != "" {
			sendStreamEvent(events, writer.Event(
				EventContentDelta,
				ContentDeltaPayload{Delta: res.Content},
			))
		}

		if len(res.ToolCalls) > 0 {
			for _, tc := range res.ToolCalls {
				sendStreamEvent(events, writer.Event(
					EventToolStarted,
					ToolActivityPayload{Name: tc.Name, Label: labelForTool(tc.Name)},
				))
			}
		}

		if len(res.ToolCalls) == 0 {
			finalContent = res.Content
			sendStreamEvent(events, writer.Event(
				EventMessageFinished,
				MessageFinishedPayload{Content: finalContent},
			))
			break
		}

		for _, tc := range res.ToolCalls {
			if l.tools.Risk(tc.Name) == tools.ToolRiskSensitiveWrite {
				pending, err := l.repo.CreatePendingToolConfirmation(ctx, userID, sessionUUID, tc.Name, tc.ArgsJSON)
				if err != nil {
					return "", fmt.Errorf("create pending tool confirmation: %w", err)
				}

				sendStreamEvent(events, writer.Event(
					EventConfirmationRequired,
					ConfirmationRequiredPayload{
						ConfirmationID: uuid.UUID(pending.ID.Bytes).String(),
						ToolName:       tc.Name,
						Label:          l.tools.Label(tc.Name),
					},
				))
				finalContent = "Preciso da sua confirmação antes de aplicar essa alteração."
				sendStreamEvent(events, writer.Event(
					EventMessageFinished,
					MessageFinishedPayload{Content: finalContent},
				))
				return finalContent, nil
			}

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

			toolMsg := llm.Message{
				Role:       llm.RoleTool,
				Content:    resultStr,
				ToolCallID: tc.ID,
			}
			messages = append(messages, toolMsg)
			lastToolResults = append(lastToolResults, resultStr)

			if _, err := l.persistTurn(ctx, userID, sessionUUID, toolMsg); err != nil {
				return "", fmt.Errorf("save tool msg: %w", err)
			}
		}
	}

	if finalContent == "" {
		finalContent = "Agent reached maximum iterations without final answer."
		sendStreamEvent(events, writer.Event(
			EventMessageFinished,
			MessageFinishedPayload{Content: finalContent},
		))
	}

	return finalContent, nil
}

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

func (l *Loop) loadHistory(ctx context.Context, userID, sessionID pgtype.UUID) ([]llm.Message, error) {
	recentMsgs, err := l.repo.GetMessages(ctx, userID, sessionID, 20, 0)
	if err != nil {
		return nil, fmt.Errorf("get messages: %w", err)
	}

	var messages []llm.Message
	for _, m := range recentMsgs {
		msg := llm.Message{
			Role:    llm.Role(m.Role),
			Content: m.Content,
		}
		if len(m.ToolCalls) > 0 {
			if err := json.Unmarshal(m.ToolCalls, &msg.ToolCalls); err != nil {
				return nil, fmt.Errorf("unmarshal tool calls: %w", err)
			}
		}
		if m.ToolCallID.Valid {
			msg.ToolCallID = m.ToolCallID.String
		}
		messages = append(messages, msg)
	}
	return messages, nil
}

func (l *Loop) persistTurn(ctx context.Context, userID, sessionID pgtype.UUID, msg llm.Message) (sqlcgen.Message, error) {
	var tcBytes []byte
	if len(msg.ToolCalls) > 0 {
		var err error
		tcBytes, err = json.Marshal(msg.ToolCalls)
		if err != nil {
			return sqlcgen.Message{}, fmt.Errorf("marshal tool calls: %w", err)
		}
	}
	var tcIDPtr *string
	if msg.ToolCallID != "" {
		tcIDPtr = &msg.ToolCallID
	}
	return l.repo.CreateMessage(ctx, userID, sessionID, string(msg.Role), msg.Content, tcBytes, tcIDPtr)
}
