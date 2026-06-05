package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const anthropicURL = "https://api.anthropic.com/v1/messages"

type anthropicClient struct {
	apiKey string
	client *http.Client
}

func NewAnthropicClient(apiKey string) Client {
	return &anthropicClient{
		apiKey: apiKey,
		client: &http.Client{},
	}
}

type anthropicContentBlock struct {
	Type      string `json:"type"`
	Text      string `json:"text,omitempty"`
	ID        string `json:"id,omitempty"`
	Name      string `json:"name,omitempty"`
	Input     any    `json:"input,omitempty"`
	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
}

type anthropicMessage struct {
	Role    string                  `json:"role"`
	Content []anthropicContentBlock `json:"content"`
}

type anthropicTool struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	InputSchema any    `json:"input_schema"`
}

type anthropicRequest struct {
	Model       string             `json:"model"`
	MaxTokens   int                `json:"max_tokens"`
	System      string             `json:"system,omitempty"`
	Messages    []anthropicMessage `json:"messages"`
	Tools       []anthropicTool    `json:"tools,omitempty"`
	Temperature float32            `json:"temperature"`
}

type anthropicResponse struct {
	Content []struct {
		Type  string `json:"type"`
		Text  string `json:"text"`
		ID    string `json:"id"`
		Name  string `json:"name"`
		Input any    `json:"input"`
	} `json:"content"`
	Usage struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
}

func (c *anthropicClient) Complete(ctx context.Context, req Request) (*Response, error) {
	if c.apiKey == "mock" || c.apiKey == "" {
		return &Response{
			Content:      "Mocked Anthropic Response",
			InputTokens:  10,
			OutputTokens: 20,
		}, nil
	}

	payload := anthropicRequest{
		Model:       "claude-3-5-sonnet-latest",
		MaxTokens:   req.MaxTokens,
		System:      req.System,
		Temperature: req.Temperature,
	}

	if payload.MaxTokens == 0 {
		payload.MaxTokens = 4096
	}

	for _, m := range req.Messages {
		if m.Role == RoleTool {
			// Anthropic tool result is sent by 'user'
			payload.Messages = append(payload.Messages, anthropicMessage{
				Role: "user",
				Content: []anthropicContentBlock{
					{
						Type:      "tool_result",
						ToolUseID: m.ToolCallID,
						Content:   m.Content,
					},
				},
			})
			continue
		}

		blocks := []anthropicContentBlock{}
		if m.Content != "" {
			blocks = append(blocks, anthropicContentBlock{
				Type: "text",
				Text: m.Content,
			})
		}

		for _, tc := range m.ToolCalls {
			var args any
			json.Unmarshal([]byte(tc.ArgsJSON), &args)
			blocks = append(blocks, anthropicContentBlock{
				Type:  "tool_use",
				ID:    tc.ID,
				Name:  tc.Name,
				Input: args,
			})
		}

		payload.Messages = append(payload.Messages, anthropicMessage{
			Role:    string(m.Role),
			Content: blocks,
		})
	}

	for _, t := range req.Tools {
		var schema any
		json.Unmarshal([]byte(t.SchemaJSON), &schema)
		payload.Tools = append(payload.Tools, anthropicTool{
			Name:        t.Name,
			Description: t.Description,
			InputSchema: schema,
		})
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("anthropic: marshal req: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, anthropicURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("anthropic: new req: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-api-key", c.apiKey)
	httpReq.Header.Set("anthropic-version", "2023-06-01")
	httpReq.Header.Set("anthropic-beta", "prompt-caching-2024-07-31")

	httpRes, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("anthropic: do req: %w", err)
	}
	defer httpRes.Body.Close()

	if httpRes.StatusCode >= 400 {
		respBody, _ := io.ReadAll(httpRes.Body)
		return nil, fmt.Errorf("anthropic API error %d: %s", httpRes.StatusCode, string(respBody))
	}

	var parsed anthropicResponse
	if err := json.NewDecoder(httpRes.Body).Decode(&parsed); err != nil {
		return nil, fmt.Errorf("anthropic: decode res: %w", err)
	}

	content := ""
	var toolCalls []ToolCall

	for _, block := range parsed.Content {
		if block.Type == "text" {
			content += block.Text
		} else if block.Type == "tool_use" {
			argsBytes, _ := json.Marshal(block.Input)
			toolCalls = append(toolCalls, ToolCall{
				ID:       block.ID,
				Name:     block.Name,
				ArgsJSON: string(argsBytes),
			})
		}
	}

	return &Response{
		Content:      content,
		ToolCalls:    toolCalls,
		InputTokens:  parsed.Usage.InputTokens,
		OutputTokens: parsed.Usage.OutputTokens,
	}, nil
}
