package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"
)

const llmHTTPTimeout = 60 * time.Second

type openAICompatClient struct {
	apiKey  string
	baseURL string
	model   string
	client  *http.Client
}

func NewOpenAICompatClient(apiKey, baseURL, model string) Client {
	return &openAICompatClient{
		apiKey:  apiKey,
		baseURL: baseURL,
		model:   model,
		client:  &http.Client{Timeout: llmHTTPTimeout},
	}
}

type openAIFunctionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type openAIToolCall struct {
	ID       string             `json:"id"`
	Type     string             `json:"type"`
	Function openAIFunctionCall `json:"function"`
}

type openAIMessage struct {
	Role       string           `json:"role"`
	Content    string           `json:"content,omitempty"`
	ToolCalls  []openAIToolCall `json:"tool_calls,omitempty"`
	ToolCallID string           `json:"tool_call_id,omitempty"`
}

type openAIFunction struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Parameters  any    `json:"parameters"`
}

type openAITool struct {
	Type     string         `json:"type"`
	Function openAIFunction `json:"function"`
}

type openAIRequest struct {
	Model       string          `json:"model"`
	Messages    []openAIMessage `json:"messages"`
	Tools       []openAITool    `json:"tools,omitempty"`
	MaxTokens   int             `json:"max_tokens,omitempty"`
	Temperature float32         `json:"temperature"`
}

type openAIResponse struct {
	Choices []struct {
		Message struct {
			Content   string           `json:"content"`
			ToolCalls []openAIToolCall `json:"tool_calls"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

func (c *openAICompatClient) Complete(ctx context.Context, req Request) (*Response, error) {
	if c.apiKey == "mock" || c.apiKey == "" {
		return &Response{
			Content:      "Mocked OpenAI Compat Response",
			InputTokens:  5,
			OutputTokens: 15,
		}, nil
	}

	payload := openAIRequest{
		Model:       c.model,
		MaxTokens:   req.MaxTokens,
		Temperature: req.Temperature,
	}

	if req.System != "" {
		payload.Messages = append(payload.Messages, openAIMessage{
			Role:    string(RoleSystem),
			Content: req.System,
		})
	}

	for _, m := range req.Messages {
		msg := openAIMessage{
			Role:       string(m.Role),
			Content:    m.Content,
			ToolCallID: m.ToolCallID,
		}
		for _, tc := range m.ToolCalls {
			msg.ToolCalls = append(msg.ToolCalls, openAIToolCall{
				ID:   tc.ID,
				Type: "function",
				Function: openAIFunctionCall{
					Name:      tc.Name,
					Arguments: tc.ArgsJSON,
				},
			})
		}
		payload.Messages = append(payload.Messages, msg)
	}

	for _, t := range req.Tools {
		var params map[string]any
		if err := json.Unmarshal([]byte(t.SchemaJSON), &params); err != nil {
			slog.Error("unmarshal tool schema", "error", err)
			return nil, fmt.Errorf("openai_compat: unmarshal tool schema: %w", err)
		}
		payload.Tools = append(payload.Tools, openAITool{
			Type: "function",
			Function: openAIFunction{
				Name:        t.Name,
				Description: t.Description,
				Parameters:  params,
			},
		})
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("openai_compat: marshal req: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("openai_compat: new req: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)

	httpRes, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("openai_compat: do req: %w", err)
	}
	defer httpRes.Body.Close()

	if httpRes.StatusCode >= 400 {
		respBody, readErr := io.ReadAll(httpRes.Body)
		if readErr != nil {
			slog.Error("read error response body", "error", readErr)
			return nil, fmt.Errorf("openai_compat API error %d", httpRes.StatusCode)
		}
		return nil, fmt.Errorf("openai_compat API error %d: %s", httpRes.StatusCode, string(respBody))
	}

	var parsed openAIResponse
	if err := json.NewDecoder(httpRes.Body).Decode(&parsed); err != nil {
		return nil, fmt.Errorf("openai_compat: decode res: %w", err)
	}

	content := ""
	var toolCalls []ToolCall
	if len(parsed.Choices) > 0 {
		content = parsed.Choices[0].Message.Content
		for _, tc := range parsed.Choices[0].Message.ToolCalls {
			toolCalls = append(toolCalls, ToolCall{
				ID:       tc.ID,
				Name:     tc.Function.Name,
				ArgsJSON: tc.Function.Arguments,
			})
		}
	}

	return &Response{
		Content:      content,
		ToolCalls:    toolCalls,
		InputTokens:  parsed.Usage.PromptTokens,
		OutputTokens: parsed.Usage.CompletionTokens,
	}, nil
}
