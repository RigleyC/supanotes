package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

const devJWTSecret = "dev-only-jwt-secret-change-me-in-production-32+chars"

type Config struct {
	Port                   string
	DatabaseURL            string
	JWTSecret              string
	CORSOrigins            []string
	OpenAIAPIKey           string
	GeminiAPIKey           string
	AnthropicAPIKey        string
	DeepSeekAPIKey         string
	TelegramBotToken       string
	FCMCredentialsFile     string
	EmbeddingsCronInterval string
	Environment            string

	// Agent chat (default: Anthropic Claude)
	AgentBaseURL string
	AgentModel   string
	AgentAPIKey  string

	// Brief generation (default: DeepSeek)
	BriefBaseURL string
	BriefModel   string

	// Inbox organize (default: OpenAI gpt-4o-mini)
	OrganizeBaseURL string
	OrganizeModel   string

	// Embeddings (default: OpenAI text-embedding-3-small)
	EmbeddingsBaseURL string
	EmbeddingsModel   string

	// Legacy — kept for backward compatibility
	OpenAICompatBaseURL    string
	OpenAICompatModel      string
	OpenAIEmbeddingsAPIKey string
	OpenAIEmbeddingsModel  string
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}

	env := strings.ToLower(strings.TrimSpace(os.Getenv("ENVIRONMENT")))
	if env == "" {
		env = "dev"
	}

	jwtSecret := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if jwtSecret == "" {
		if env != "dev" {
			return nil, fmt.Errorf("config: JWT_SECRET is required outside dev")
		}
		jwtSecret = devJWTSecret
	}

	corsOrigins := parseCORSOrigins(os.Getenv("CORS_ORIGINS"), env)

	return &Config{
		Port:                   port,
		Environment:            env,
		DatabaseURL:            os.Getenv("DATABASE_URL"),
		JWTSecret:              jwtSecret,
		CORSOrigins:            corsOrigins,
		OpenAIAPIKey:           os.Getenv("OPENAI_API_KEY"),
		GeminiAPIKey:           os.Getenv("GEMINI_API_KEY"),
		AnthropicAPIKey:        os.Getenv("ANTHROPIC_API_KEY"),
		DeepSeekAPIKey:         os.Getenv("DEEPSEEK_API_KEY"),
		TelegramBotToken:       os.Getenv("TELEGRAM_BOT_TOKEN"),
		FCMCredentialsFile:     os.Getenv("FCM_CREDENTIALS_FILE"),
		EmbeddingsCronInterval: defaultIfEmpty(os.Getenv("EMBEDDINGS_CRON_INTERVAL"), "*/30 * * * * *"),
		AgentBaseURL:           os.Getenv("AGENT_BASE_URL"),
		AgentModel:             os.Getenv("AGENT_MODEL"),
		AgentAPIKey:            os.Getenv("AGENT_API_KEY"),
		BriefBaseURL:           os.Getenv("BRIEF_BASE_URL"),
		BriefModel:             os.Getenv("BRIEF_MODEL"),
		OrganizeBaseURL:        firstNonEmpty(os.Getenv("ORGANIZE_BASE_URL"), os.Getenv("OPENAI_COMPAT_BASE_URL")),
		OrganizeModel:          firstNonEmpty(os.Getenv("ORGANIZE_MODEL"), os.Getenv("OPENAI_COMPAT_MODEL")),
		EmbeddingsBaseURL:      os.Getenv("EMBEDDINGS_BASE_URL"),
		EmbeddingsModel:        firstNonEmpty(os.Getenv("EMBEDDINGS_MODEL"), os.Getenv("OPENAI_EMBEDDINGS_MODEL")),
		OpenAICompatBaseURL:    os.Getenv("OPENAI_COMPAT_BASE_URL"),
		OpenAICompatModel:      os.Getenv("OPENAI_COMPAT_MODEL"),
		OpenAIEmbeddingsAPIKey: os.Getenv("OPENAI_EMBEDDINGS_API_KEY"),
		OpenAIEmbeddingsModel:  os.Getenv("OPENAI_EMBEDDINGS_MODEL"),
	}, nil
}

func (c *Config) IsDev() bool {
	return strings.EqualFold(c.Environment, "dev")
}

func defaultIfEmpty(s, def string) string {
	if s == "" {
		return def
	}
	return s
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func (c *Config) Addr() string {
	return fmt.Sprintf(":%s", c.Port)
}

// parseCORSOrigins splits a comma-separated CORS_ORIGINS value into a
// slice, trimming whitespace. In dev mode with no explicit override,
// it defaults to wildcard; outside dev, an empty list disables CORS.
func parseCORSOrigins(raw, env string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		if strings.EqualFold(env, "dev") {
			return []string{"*"}
		}
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
