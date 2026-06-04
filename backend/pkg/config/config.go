package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

const devJWTSecret = "dev-only-jwt-secret-change-me-in-production-32+chars"

type Config struct {
	Port         string
	DatabaseURL  string
	JWTSecret    string
	OpenAIAPIKey string
	GeminiAPIKey string
	Environment  string
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

	return &Config{
		Port:         port,
		Environment:  env,
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		JWTSecret:    jwtSecret,
		OpenAIAPIKey: os.Getenv("OPENAI_API_KEY"),
		GeminiAPIKey: os.Getenv("GEMINI_API_KEY"),
	}, nil
}

func (c *Config) IsDev() bool {
	return strings.EqualFold(c.Environment, "dev")
}

func (c *Config) Addr() string {
	return fmt.Sprintf(":%s", c.Port)
}
