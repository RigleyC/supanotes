package llm

import "context"

type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
	RoleSystem    Role = "system"
	RoleTool      Role = "tool"
)

type ToolCall struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	ArgsJSON string `json:"args_json"`
}

type Tool struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	SchemaJSON  string `json:"schema_json"` // JSON Schema as a string
}

type Message struct {
	Role       Role
	Content    string
	ToolCalls  []ToolCall
	ToolCallID string
}

type Request struct {
	Messages    []Message
	System      string
	Tools       []Tool
	MaxTokens   int
	Temperature float32
}

type Response struct {
	Content      string
	ToolCalls    []ToolCall
	InputTokens  int
	OutputTokens int
	CacheHits    int
}

type Client interface {
	Complete(ctx context.Context, req Request) (*Response, error)
}
