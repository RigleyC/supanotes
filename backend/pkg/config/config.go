package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	Port         string
	DatabaseURL  string
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

	return &Config{
		Port:         port,
		Environment:  env,
		DatabaseURL:  os.Getenv("DATABASE_URL"),
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
