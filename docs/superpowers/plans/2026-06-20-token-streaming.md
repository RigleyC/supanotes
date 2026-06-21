# Streaming Real de Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modify the Go backend to stream LLM response tokens chunk-by-chunk in real-time to the Flutter client, instead of retrieving the full response synchronously and sending it as a single block.

**Architecture:** Extend the `llm.Client` interface to support a `CompleteStream` method that accepts a token callback. Implement this method for both the OpenAI-compatible HTTP client and the Anthropic HTTP client using Server-Sent Events (SSE) parsing. Update the agent orchestration loop to stream content deltas as they arrive.

**Tech Stack:** Go (REST API, Server-Sent Events, `bufio.Reader` for HTTP stream parsing).

---

## Proposed Changes

### Task 1: Extend `llm.Client` Interface

**Files:**
- Modify: [client.go](file:///d:/projects/supanotes/backend/pkg/llm/client.go)

- [ ] **Step 1: Add CompleteStream method to Client interface**
  Add the `CompleteStream` method signature to `Client`:
  ```go
  type Client interface {
  	Complete(ctx context.Context, req Request) (*Response, error)
  	CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error)
  }
  ```

---

### Task 2: Implement `CompleteStream` in `openAICompatClient`

**Files:**
- Modify: [openai_compat.go](file:///d:/projects/supanotes/backend/pkg/llm/openai_compat.go)

- [ ] **Step 1: Add implementation of CompleteStream to openAICompatClient**
  Implement `CompleteStream` using SSE parsing:
  ```go
  func (c *openAICompatClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
  	if c.apiKey == "mock" || c.apiKey == "" {
  		onToken("Mocked OpenAI Compat Streamed Response")
  		return &Response{
  			Content:      "Mocked OpenAI Compat Streamed Response",
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

  	// Construct the streaming request URL
  	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(body))
  	if err != nil {
  		return nil, fmt.Errorf("openai_compat: new req: %w", err)
  	}

  	httpReq.Header.Set("Content-Type", "application/json")
  	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)

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
  	httpReq.Body = io.NopCloser(bytes.NewReader(streamBody))
  	httpReq.ContentLength = int64(len(streamBody))

  	httpRes, err := c.client.Do(httpReq)
  	if err != nil {
  		return nil, fmt.Errorf("openai_compat: do req: %w", err)
  	}
  	defer httpRes.Body.Close()

  	if httpRes.StatusCode >= 400 {
  		respBody, readErr := io.ReadAll(httpRes.Body)
  		if readErr != nil {
  			return nil, fmt.Errorf("openai_compat API error %d", httpRes.StatusCode)
  		}
  		return nil, fmt.Errorf("openai_compat API error %d: %s", httpRes.StatusCode, string(respBody))
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
  		if dataStr == "[DONE]" {
  			break
  		}

  		var chunk struct {
  			Choices []struct {
  				Delta struct {
  					Content   string `json:"content"`
  					ToolCalls []struct {
  						Index    int    `json:"index"`
  						ID       string `json:"id"`
  						Type     string `json:"type"`
  						Function struct {
  							Name      string `json:"name"`
  							Arguments string `json:"arguments"`
  						} `json:"function"`
  					} `json:"tool_calls"`
  				} `json:"delta"`
  			} `json:"choices"`
  		}

  		if err := json.Unmarshal([]byte(dataStr), &chunk); err != nil {
  			continue // Skip malformed chunks
  		}

  		if len(chunk.Choices) > 0 {
  			delta := chunk.Choices[0].Delta
  			if delta.Content != "" {
  				contentBuilder.WriteString(delta.Content)
  				if err := onToken(delta.Content); err != nil {
  					return nil, fmt.Errorf("onToken callback error: %w", err)
  				}
  			}

  			for _, tcChunk := range delta.ToolCalls {
  				state, ok := toolCallsMap[tcChunk.Index]
  				if !ok {
  					state = &toolCallState{}
  					toolCallsMap[tcChunk.Index] = state
  				}
  				if tcChunk.ID != "" {
  					state.id = tcChunk.ID
  				}
  				if tcChunk.Function.Name != "" {
  					state.name = tcChunk.Function.Name
  				}
  				if tcChunk.Function.Arguments != "" {
  					state.argsBuilder.WriteString(tcChunk.Function.Arguments)
  				}
  			}
  		}
  	}

  	// Convert accumulated tool calls
  	var toolCalls []ToolCall
  	for i := 0; i < len(toolCallsMap); i++ {
  		if state, ok := toolCallsMap[i]; ok {
  			toolCalls = append(toolCalls, ToolCall{
  				ID:       state.id,
  				Name:     state.name,
  				ArgsJSON: state.argsBuilder.String(),
  			})
  		}
  	}

  	return &Response{
  		Content:   contentBuilder.String(),
  		ToolCalls: toolCalls,
  	}, nil
  }
  ```

- [ ] **Step 2: Add imports to openai_compat.go**
  Add `bufio`, `strings`, `io` if not already present in `openai_compat.go`.

---

### Task 3: Implement `CompleteStream` in `anthropicClient`

**Files:**
- Modify: [anthropic.go](file:///d:/projects/supanotes/backend/pkg/llm/anthropic.go)

- [ ] **Step 1: Add implementation of CompleteStream to anthropicClient**
  Implement `CompleteStream` using SSE parsing for Anthropic format:
  ```go
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

  	var toolCalls []ToolCall
  	for i := 0; i < len(toolCallsMap); i++ {
  		if state, ok := toolCallsMap[i]; ok {
  			toolCalls = append(toolCalls, ToolCall{
  				ID:       state.id,
  				Name:     state.name,
  				ArgsJSON: state.argsBuilder.String(),
  			})
  		}
  	}

  	return &Response{
  		Content:   contentBuilder.String(),
  		ToolCalls: toolCalls,
  	}, nil
  }
  ```

- [ ] **Step 2: Add imports to anthropic.go**
  Add `bufio`, `strings`, `io` if not already present.

---

### Task 4: Implement `CompleteStream` in `retryClient` Decorator

**Files:**
- Modify: [retry.go](file:///d:/projects/supanotes/backend/pkg/llm/retry.go)

- [ ] **Step 1: Add CompleteStream implementation**
  Add `CompleteStream` to `retryClient` (delegating to base client):
  ```go
  func (r *retryClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
  	// Retrying streaming requests is complex once tokens start emitting,
  	// so we delegate directly to the base client.
  	return r.base.CompleteStream(ctx, req, onToken)
  }
  ```

---

### Task 5: Update Tests and Mock Clients

**Files:**
- Modify: [loop_test.go](file:///d:/projects/supanotes/backend/internal/agent/loop_test.go)

- [ ] **Step 1: Add CompleteStream to stubLoopLLMClient**
  Implement `CompleteStream` in `stubLoopLLMClient` to simulate streaming:
  ```go
  func (s *stubLoopLLMClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
  	res, err := s.Complete(ctx, req)
  	if err != nil {
  		return nil, err
  	}
  	if res.Content != "" {
  		onToken(res.Content)
  	}
  	return res, nil
  }
  ```

---

### Task 6: Modify `Loop.doChat` to Stream Content Deltas

**Files:**
- Modify: [loop.go](file:///d:/projects/supanotes/backend/internal/agent/loop.go)

- [ ] **Step 1: Change Complete to CompleteStream in Loop.doChat**
  Locate lines 181 and 198:
  ```go
  res, err := client.Complete(ctx, req)
  ```
  Replace them to use `CompleteStream`, passing a callback that sends a `EventContentDelta` event for every token chunk:
  ```go
  res, err := client.CompleteStream(ctx, req, func(token string) error {
  	sendStreamEvent(events, writer.Event(
  		EventContentDelta,
  		ContentDeltaPayload{Delta: token},
  	))
  	return nil
  })
  ```

- [ ] **Step 2: Update fallback request completion in Loop.doChat**
  Locate line 198 (fallback completion):
  ```go
  res, err = client.Complete(ctx, fallbackReq)
  ```
  Replace it similarly:
  ```go
  res, err = client.CompleteStream(ctx, fallbackReq, func(token string) error {
  	sendStreamEvent(events, writer.Event(
  		EventContentDelta,
  		ContentDeltaPayload{Delta: token},
  	))
  	return nil
  })
  ```

- [ ] **Step 3: Remove synchronous EventContentDelta emitter**
  Since the deltas are now emitted in real time during the stream, we should remove the redundant synchronous content event sent after completion.
  Locate lines 225-230:
  ```go
  if res.Content != "" {
  	sendStreamEvent(events, writer.Event(
  		EventContentDelta,
  		ContentDeltaPayload{Delta: res.Content},
  	))
  }
  ```
  **Remove these lines completely** to prevent double-printing the response content on the frontend.

---

## Verification Plan

### Automated Tests
- Run backend agent tests:
  `go test -v ./backend/internal/agent/...`

### Manual Verification
1. Run backend server locally:
   `go run backend/cmd/server/main.go`
2. Run Flutter app on Android/iOS/Simulator in debug mode.
3. Open chat page and send a query.
4. Verify that responses appear word-by-word in real-time as tokens arrive, rather than appearing all at once after a loading indicator.
