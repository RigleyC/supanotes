package agent

import (
	"sync"
	"time"
)

type ToolCallTrace struct {
	ToolName string        `json:"tool_name"`
	Args     string        `json:"args"`
	Latency  time.Duration `json:"latency"`
	Error    string        `json:"error,omitempty"`
}

type ExecutionTrace struct {
	SessionID        string          `json:"session_id"`
	UserID           string          `json:"user_id"`
	UserMessage      string          `json:"user_message"`
	DetectedIntent   Intent          `json:"detected_intent"`
	PlannerOutput    string          `json:"planner_output"`
	RetrievedContext string          `json:"retrieved_context"`
	PromptSize       int             `json:"prompt_size"`
	TokenCount       int             `json:"token_count"`
	ToolCalls        []ToolCallTrace `json:"tool_calls"`
	IterationCount   int             `json:"iteration_count"`
	CompletionReason string          `json:"completion_reason"`
	FinalResponse    string          `json:"final_response"`
	CreatedAt        time.Time       `json:"created_at"`
}

type TraceStore struct {
	mu     sync.RWMutex
	traces map[string][]*ExecutionTrace // key: sessionID
}

var GlobalTraceStore = &TraceStore{
	traces: make(map[string][]*ExecutionTrace),
}

func (ts *TraceStore) AddTrace(sessionID string, trace *ExecutionTrace) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	ts.traces[sessionID] = append(ts.traces[sessionID], trace)
	// Keep only the last 20 traces per session to avoid memory bloat
	if len(ts.traces[sessionID]) > 20 {
		ts.traces[sessionID] = ts.traces[sessionID][len(ts.traces[sessionID])-20:]
	}
}

func (ts *TraceStore) GetTraces(sessionID string) []*ExecutionTrace {
	ts.mu.RLock()
	defer ts.mu.RUnlock()
	return ts.traces[sessionID]
}
