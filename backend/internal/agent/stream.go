package agent

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type SSEEvent struct {
	Type string
	Data string
}

func (l *Loop) ChatStream(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- SSEEvent) error {
	defer close(events)

	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return fmt.Errorf("invalid session id: %w", err)
	}

	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}

	_, err = l.repo.CreateMessage(ctx, userID, sessionUUID, string(llm.RoleUser), userMessage, nil, nil)
	if err != nil {
		return fmt.Errorf("save user msg: %w", err)
	}

	sysPrompt, err := l.ctxBldr.Build(ctx, userID, sessionUUID, userMessage)
	if err != nil {
		return fmt.Errorf("build context: %w", err)
	}

	client := l.llmFact.For(llm.TaskTypeAgentic)
	tools := l.tools.GetTools()

	messages, err := l.loadHistory(ctx, userID, sessionUUID)
	if err != nil {
		return fmt.Errorf("load history: %w", err)
	}

	for i := 0; i < 5; i++ {
		req := llm.Request{
			System:      sysPrompt,
			Messages:    messages,
			Tools:       tools,
			MaxTokens:   4000,
			Temperature: 0.7,
		}

		res, err := client.Complete(ctx, req)
		if err != nil {
			return fmt.Errorf("llm call: %w", err)
		}

		assistMsg := llm.Message{
			Role:      llm.RoleAssistant,
			Content:   res.Content,
			ToolCalls: res.ToolCalls,
		}
		messages = append(messages, assistMsg)

		if _, err := l.persistTurn(ctx, userID, sessionUUID, assistMsg); err != nil {
			return fmt.Errorf("save assistant msg: %w", err)
		}

		if res.Content != "" {
			events <- SSEEvent{Type: "content_delta", Data: res.Content}
		}

		if len(res.ToolCalls) > 0 {
			for _, tc := range res.ToolCalls {
				tcJSON, _ := json.Marshal(tc)
				events <- SSEEvent{Type: "tool_use", Data: string(tcJSON)}
			}
		}

		if len(res.ToolCalls) == 0 {
			events <- SSEEvent{Type: "done", Data: res.Content}
			return nil
		}

		for _, tc := range res.ToolCalls {
			resultStr, err := l.tools.Execute(ctx, userID, tc.Name, tc.ArgsJSON)
			if err != nil {
				resultStr = fmt.Sprintf("Error executing tool: %v", err)
			}

			toolMsg := llm.Message{
				Role:       llm.RoleTool,
				Content:    resultStr,
				ToolCallID: tc.ID,
			}
			messages = append(messages, toolMsg)

			if _, err := l.persistTurn(ctx, userID, sessionUUID, toolMsg); err != nil {
				return fmt.Errorf("save tool msg: %w", err)
			}

			events <- SSEEvent{Type: "tool_result", Data: resultStr}
		}
	}

	events <- SSEEvent{Type: "done", Data: "Agent reached maximum iterations."}
	return nil
}
