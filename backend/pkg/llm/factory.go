package llm

import "github.com/RigleyC/supanotes/pkg/config"

type TaskType string

const (
	TaskTypeAgentic  TaskType = "agentic"
	TaskTypeGenerate TaskType = "generate"
	// TaskTypeInboxOrganize routes to the OpenAI-compatible client
	// (provider chosen at deploy time via env). Kept separate from
	// TaskTypeGenerate so we can swap provider/model per feature
	// without affecting other generate-path consumers.
	TaskTypeInboxOrganize TaskType = "inbox_organize"
)

type Factory interface {
	For(task TaskType) Client
}

type factory struct {
	anthropic     Client
	generate      Client
	inboxOrganize Client
}

func NewFactory(cfg *config.Config) Factory {
	anthropicBase := NewAnthropicClient(cfg.AnthropicAPIKey)
	anthropicWithRetry := WithRetry(anthropicBase, 3)

	generateBase := NewOpenAICompatClient(cfg.DeepSeekAPIKey, "https://api.deepseek.com/v1/chat/completions", "deepseek-chat")
	generateWithRetry := WithRetry(generateBase, 3)

	// Inbox-organize uses the OpenAI-compatible client configured via
	// env. Both key fields fall back to a no-op "mock" path in
	// openai_compat.go so leaving them empty is safe in dev.
	openAICompatBase := NewOpenAICompatClient(
		cfg.OpenAIAPIKey,
		defaultIfEmpty(cfg.OpenAICompatBaseURL, "https://api.openai.com/v1/chat/completions"),
		defaultIfEmpty(cfg.OpenAICompatModel, "gpt-4o-mini"),
	)
	openAICompatWithRetry := WithRetry(openAICompatBase, 3)

	return &factory{
		anthropic:     anthropicWithRetry,
		generate:      generateWithRetry,
		inboxOrganize: openAICompatWithRetry,
	}
}

func (f *factory) For(task TaskType) Client {
	switch task {
	case TaskTypeAgentic:
		return f.anthropic
	case TaskTypeInboxOrganize:
		return f.inboxOrganize
	default:
		return f.generate
	}
}

func defaultIfEmpty(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
