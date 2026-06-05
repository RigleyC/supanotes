package agent

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

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

func (l *Loop) Chat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string) (string, error) {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return "", fmt.Errorf("invalid session id: %w", err)
	}

	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}

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
	tools := l.tools.GetTools()

	// Initial message history array
	var messages []llm.Message
	
	recentMsgs, err := l.repo.GetMessages(ctx, userID, sessionUUID, 20, 0)
	if err == nil {
		for _, m := range recentMsgs {
			msg := llm.Message{
				Role:    llm.Role(m.Role),
				Content: m.Content,
			}
			if len(m.ToolCalls) > 0 {
				json.Unmarshal(m.ToolCalls, &msg.ToolCalls)
			}
			if m.ToolCallID.Valid {
				msg.ToolCallID = m.ToolCallID.String
			}
			messages = append(messages, msg)
		}
	}

	finalContent := ""
	
	// 4. Tool Calling Loop (max 5 iterations)
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
			return "", fmt.Errorf("llm call: %w", err)
		}

		// Save the assistant's message to our local memory chain
		assistMsg := llm.Message{
			Role:      llm.RoleAssistant,
			Content:   res.Content,
			ToolCalls: res.ToolCalls,
		}
		messages = append(messages, assistMsg)

		var tcBytes []byte
		if len(res.ToolCalls) > 0 {
			tcBytes, _ = json.Marshal(res.ToolCalls)
		}

		// Also save to database
		_, err = l.repo.CreateMessage(ctx, userID, sessionUUID, string(llm.RoleAssistant), res.Content, tcBytes, nil)
		if err != nil {
			return "", fmt.Errorf("save assistant msg: %w", err)
		}

		// If no tools were called, we are done!
		if len(res.ToolCalls) == 0 {
			finalContent = res.Content
			break
		}

		// Execute tools
		for _, tc := range res.ToolCalls {
			resultStr, err := l.tools.Execute(ctx, userID, tc.Name, tc.ArgsJSON)
			if err != nil {
				resultStr = fmt.Sprintf("Error executing tool: %v", err)
			}

			// Save tool response locally
			toolMsg := llm.Message{
				Role:       llm.RoleTool,
				Content:    resultStr,
				ToolCallID: tc.ID,
			}
			messages = append(messages, toolMsg)

			var tcIDStr *string
			if tc.ID != "" {
				tcIDStr = &tc.ID
			}
			_, err = l.repo.CreateMessage(ctx, userID, sessionUUID, string(llm.RoleTool), resultStr, nil, tcIDStr)
			if err != nil {
				return "", fmt.Errorf("save tool msg: %w", err)
			}
		}
	}

	if finalContent == "" {
		finalContent = "Agent reached maximum iterations without final answer."
	}

	return finalContent, nil
}
