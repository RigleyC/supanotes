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
	TelegramWebhookSecret  string
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

	// Storage (S3-compatible: AWS, MinIO, Supabase, GCS)
	S3Endpoint        string // S3_ENDPOINT — e.g. https://s3.amazonaws.com or http://minio:9000
	S3Region          string // S3_REGION
	S3Bucket          string // S3_BUCKET
	S3AccessKeyID     string // S3_ACCESS_KEY_ID
	S3SecretAccessKey string // S3_SECRET_ACCESS_KEY
	S3PublicBaseURL   string // S3_PUBLIC_BASE_URL — public URL prefix for serving files
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
		TelegramWebhookSecret:  os.Getenv("TELEGRAM_WEBHOOK_SECRET"),
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
		S3Endpoint:             firstNonEmpty(os.Getenv("S3_ENDPOINT"), os.Getenv("AWS_ENDPOINT_URL_S3")),
		S3Region:               firstNonEmpty(os.Getenv("S3_REGION"), os.Getenv("AWS_REGION")),
		S3Bucket:               firstNonEmpty(os.Getenv("S3_BUCKET"), os.Getenv("BUCKET_NAME")),
		S3AccessKeyID:          firstNonEmpty(os.Getenv("S3_ACCESS_KEY_ID"), os.Getenv("AWS_ACCESS_KEY_ID")),
		S3SecretAccessKey:      firstNonEmpty(os.Getenv("S3_SECRET_ACCESS_KEY"), os.Getenv("AWS_SECRET_ACCESS_KEY")),
		S3PublicBaseURL:        firstNonEmpty(os.Getenv("S3_PUBLIC_BASE_URL"), buildTigrisPublicBaseURL(firstNonEmpty(os.Getenv("S3_BUCKET"), os.Getenv("BUCKET_NAME")), firstNonEmpty(os.Getenv("S3_ENDPOINT"), os.Getenv("AWS_ENDPOINT_URL_S3")))),
	}, nil
}

func buildTigrisPublicBaseURL(bucket, endpoint string) string {
	if bucket != "" && strings.Contains(endpoint, "tigris.dev") {
		return fmt.Sprintf("https://%s.fly.storage.tigris.dev", bucket)
	}
	return ""
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
