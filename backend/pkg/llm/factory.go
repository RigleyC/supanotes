package llm

import "github.com/RigleyC/supanotes/pkg/config"

type TaskType string

const (
	TaskTypeAgentic  TaskType = "agentic"
	TaskTypeGenerate TaskType = "generate"
)

type Factory interface {
	For(task TaskType) Client
}

type factory struct {
	anthropic Client
	generate  Client
}

func NewFactory(cfg *config.Config) Factory {
	anthropicBase := NewAnthropicClient(cfg.AnthropicAPIKey)
	anthropicWithRetry := WithRetry(anthropicBase, 3)

	generateBase := NewOpenAICompatClient(cfg.DeepSeekAPIKey, "https://api.deepseek.com/v1/chat/completions", "deepseek-chat")
	generateWithRetry := WithRetry(generateBase, 3)

	return &factory{
		anthropic: anthropicWithRetry,
		generate:  generateWithRetry,
	}
}

func (f *factory) For(task TaskType) Client {
	if task == TaskTypeAgentic {
		return f.anthropic
	}
	return f.generate
}
