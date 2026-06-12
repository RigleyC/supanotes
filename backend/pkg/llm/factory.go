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
	agent         Client
	generate      Client
	inboxOrganize Client
}

func NewFactory(cfg *config.Config) Factory {
	var agentClient Client
	if cfg.AgentBaseURL != "" {
		apiKey := cfg.AgentAPIKey
		if apiKey == "" {
			apiKey = cfg.AnthropicAPIKey
		}
		model := defaultIfEmpty(cfg.AgentModel, "gpt-4o")
		agentBase := NewOpenAICompatClient(apiKey, cfg.AgentBaseURL, model)
		agentClient = WithRetry(agentBase, 3)
	} else {
		anthropicBase := NewAnthropicClient(cfg.AnthropicAPIKey)
		agentClient = WithRetry(anthropicBase, 3)
	}

	briefBase := NewOpenAICompatClient(
		cfg.DeepSeekAPIKey,
		defaultIfEmpty(cfg.BriefBaseURL, "https://api.deepseek.com/v1/chat/completions"),
		defaultIfEmpty(cfg.BriefModel, "deepseek-chat"),
	)
	briefWithRetry := WithRetry(briefBase, 3)

	organizeBase := NewOpenAICompatClient(
		cfg.OpenAIAPIKey,
		defaultIfEmpty(cfg.OrganizeBaseURL, "https://api.openai.com/v1/chat/completions"),
		defaultIfEmpty(cfg.OrganizeModel, "gpt-4o-mini"),
	)
	organizeWithRetry := WithRetry(organizeBase, 3)

	return &factory{
		agent:         agentClient,
		generate:      briefWithRetry,
		inboxOrganize: organizeWithRetry,
	}
}

func (f *factory) For(task TaskType) Client {
	switch task {
	case TaskTypeAgentic:
		return f.agent
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
