package llm

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sort"
	"strings"
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
	Type         string            `json:"type"`
	Text         string            `json:"text,omitempty"`
	ID           string            `json:"id,omitempty"`
	Name         string            `json:"name,omitempty"`
	Input        any               `json:"input,omitempty"`
	ToolUseID    string            `json:"tool_use_id,omitempty"`
	Content      string            `json:"content,omitempty"`
	CacheControl map[string]string `json:"cache_control,omitempty"`
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
	Model       string                  `json:"model"`
	MaxTokens   int                     `json:"max_tokens"`
	System      []anthropicContentBlock `json:"system,omitempty"`
	Messages    []anthropicMessage      `json:"messages"`
	Tools       []anthropicTool         `json:"tools,omitempty"`
	Temperature float32                 `json:"temperature"`
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
		InputTokens          int  `json:"input_tokens"`
		OutputTokens         int  `json:"output_tokens"`
		CacheReadInputTokens *int `json:"cache_read_input_tokens,omitempty"`
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
		Model:       "claude-sonnet-4-20250514",
		MaxTokens:   req.MaxTokens,
		Temperature: req.Temperature,
	}
	if req.System != "" {
		payload.System = []anthropicContentBlock{{
			Type:         "text",
			Text:         req.System,
			CacheControl: map[string]string{"type": "ephemeral"},
		}}
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
			if err := json.Unmarshal([]byte(tc.ArgsJSON), &args); err != nil {
				slog.Error("unmarshal tool call args", "error", err)
				return nil, fmt.Errorf("anthropic: unmarshal tool call args: %w", err)
			}
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
		if err := json.Unmarshal([]byte(t.SchemaJSON), &schema); err != nil {
			slog.Error("unmarshal tool schema", "error", err)
			return nil, fmt.Errorf("anthropic: unmarshal tool schema: %w", err)
		}
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
		respBody, readErr := io.ReadAll(httpRes.Body)
		if readErr != nil {
			slog.Error("read error response body", "error", readErr)
			return nil, fmt.Errorf("anthropic API error %d", httpRes.StatusCode)
		}
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
			argsBytes, marshalErr := json.Marshal(block.Input)
			if marshalErr != nil {
				slog.Error("marshal tool use input", "error", marshalErr)
				return nil, fmt.Errorf("anthropic: marshal tool use input: %w", marshalErr)
			}
			toolCalls = append(toolCalls, ToolCall{
				ID:       block.ID,
				Name:     block.Name,
				ArgsJSON: string(argsBytes),
			})
		}
	}

	cacheHits := 0
	if parsed.Usage.CacheReadInputTokens != nil {
		cacheHits = *parsed.Usage.CacheReadInputTokens
	}

	return &Response{
		Content:      content,
		ToolCalls:    toolCalls,
		InputTokens:  parsed.Usage.InputTokens,
		OutputTokens: parsed.Usage.OutputTokens,
		CacheHits:    cacheHits,
	}, nil
}

func (c *anthropicClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
	if c.apiKey == "mock" || c.apiKey == "" {
		onToken("Mocked Anthropic Streamed Response")
		return &Response{
			Content:      "Mocked Anthropic Streamed Response",
			InputTokens:  10,
			OutputTokens: 20,
		}, nil
	}

	payload := anthropicRequest{
		Model:       "claude-sonnet-4-20250514",
		MaxTokens:   req.MaxTokens,
		Temperature: req.Temperature,
	}
	if req.System != "" {
		payload.System = []anthropicContentBlock{{
			Type:         "text",
			Text:         req.System,
			CacheControl: map[string]string{"type": "ephemeral"},
		}}
	}

	if payload.MaxTokens == 0 {
		payload.MaxTokens = 4096
	}

	for _, m := range req.Messages {
		if m.Role == RoleTool {
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
			if err := json.Unmarshal([]byte(tc.ArgsJSON), &args); err != nil {
				return nil, fmt.Errorf("anthropic: unmarshal tool call args: %w", err)
			}
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
		if err := json.Unmarshal([]byte(t.SchemaJSON), &schema); err != nil {
			return nil, fmt.Errorf("anthropic: unmarshal tool schema: %w", err)
		}
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

	// Override Request JSON to ask for streaming
	var rawMap map[string]any
	if err := json.Unmarshal(body, &rawMap); err != nil {
		return nil, err
	}
	rawMap["stream"] = true
	streamBody, err := json.Marshal(rawMap)
	if err != nil {
		return nil, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, anthropicURL, bytes.NewReader(streamBody))
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
		respBody, readErr := io.ReadAll(httpRes.Body)
		if readErr != nil {
			return nil, fmt.Errorf("anthropic API error %d", httpRes.StatusCode)
		}
		return nil, fmt.Errorf("anthropic API error %d: %s", httpRes.StatusCode, string(respBody))
	}

	var contentBuilder strings.Builder
	
	// Accumulate Tool Calls
	type toolCallState struct {
		id          string
		name        string
		argsBuilder strings.Builder
	}
	toolCallsMap := make(map[int]*toolCallState)

	reader := bufio.NewReader(httpRes.Body)
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			return nil, fmt.Errorf("read stream line: %w", err)
		}

		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}

		if !bytes.HasPrefix(line, []byte("data: ")) {
			continue
		}

		dataStr := string(line[6:])

		var event struct {
			Type string `json:"type"`
			// For content_block_start
			Index        int `json:"index"`
			ContentBlock *struct {
				Type string `json:"type"`
				ID   string `json:"id"`
				Name string `json:"name"`
			} `json:"content_block,omitempty"`
			// For content_block_delta
			Delta *struct {
				Type        string `json:"type"`
				Text        string `json:"text,omitempty"`
				PartialJSON string `json:"partial_json,omitempty"`
			} `json:"delta,omitempty"`
		}

		if err := json.Unmarshal([]byte(dataStr), &event); err != nil {
			continue
		}

		switch event.Type {
		case "content_block_start":
			if event.ContentBlock != nil && event.ContentBlock.Type == "tool_use" {
				toolCallsMap[event.Index] = &toolCallState{
					id:   event.ContentBlock.ID,
					name: event.ContentBlock.Name,
				}
			}
		case "content_block_delta":
			if event.Delta != nil {
				if event.Delta.Type == "text_delta" && event.Delta.Text != "" {
					contentBuilder.WriteString(event.Delta.Text)
					if err := onToken(event.Delta.Text); err != nil {
						return nil, fmt.Errorf("onToken callback error: %w", err)
					}
				} else if event.Delta.Type == "input_json_delta" && event.Delta.PartialJSON != "" {
					if state, ok := toolCallsMap[event.Index]; ok {
						state.argsBuilder.WriteString(event.Delta.PartialJSON)
					}
				}
			}
		case "message_stop":
			break
		}
	}

	// Convert accumulated tool calls in sorted index order
	keys := make([]int, 0, len(toolCallsMap))
	for k := range toolCallsMap {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	var toolCalls []ToolCall
	for _, k := range keys {
		state := toolCallsMap[k]
		toolCalls = append(toolCalls, ToolCall{
			ID:       state.id,
			Name:     state.name,
			ArgsJSON: state.argsBuilder.String(),
		})
	}

	return &Response{
		Content:   contentBuilder.String(),
		ToolCalls: toolCalls,
	}, nil
}
