package config

import (
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	// Set all known vars to empty so we observe the defaults.
	for _, k := range []string{"PORT", "ENVIRONMENT", "DATABASE_URL", "OPENAI_API_KEY", "GEMINI_API_KEY"} {
		t.Setenv(k, "")
	}

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() returned error: %v", err)
	}

	if cfg.Port != "8080" {
		t.Errorf("Port: want 8080, got %q", cfg.Port)
	}
	if cfg.Environment != "dev" {
		t.Errorf("Environment: want dev, got %q", cfg.Environment)
	}
	if cfg.DatabaseURL != "" {
		t.Errorf("DatabaseURL: want empty by default, got %q", cfg.DatabaseURL)
	}
	if cfg.OpenAIAPIKey != "" {
		t.Errorf("OpenAIAPIKey: want empty by default, got %q", cfg.OpenAIAPIKey)
	}
	if cfg.GeminiAPIKey != "" {
		t.Errorf("GeminiAPIKey: want empty by default, got %q", cfg.GeminiAPIKey)
	}
}

func TestLoad_FromEnv(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("ENVIRONMENT", "prod")
	t.Setenv("DATABASE_URL", "postgres://user:pass@db:5432/app?sslmode=disable")
	t.Setenv("OPENAI_API_KEY", "sk-test-openai")
	t.Setenv("GEMINI_API_KEY", "gem-test-key")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() returned error: %v", err)
	}

	if cfg.Port != "9090" {
		t.Errorf("Port: want 9090, got %q", cfg.Port)
	}
	if cfg.Environment != "prod" {
		t.Errorf("Environment: want prod, got %q", cfg.Environment)
	}
	if cfg.DatabaseURL != "postgres://user:pass@db:5432/app?sslmode=disable" {
		t.Errorf("DatabaseURL mismatch: %q", cfg.DatabaseURL)
	}
	if cfg.OpenAIAPIKey != "sk-test-openai" {
		t.Errorf("OpenAIAPIKey mismatch: %q", cfg.OpenAIAPIKey)
	}
	if cfg.GeminiAPIKey != "gem-test-key" {
		t.Errorf("GeminiAPIKey mismatch: %q", cfg.GeminiAPIKey)
	}
}

func TestIsDev(t *testing.T) {
	tests := []struct {
		env  string
		want bool
	}{
		{"dev", true},
		{"DEV", true},
		{"development", false},
		{"prod", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.env, func(t *testing.T) {
			cfg := &Config{Environment: tt.env}
			if got := cfg.IsDev(); got != tt.want {
				t.Errorf("IsDev() for %q: want %v, got %v", tt.env, tt.want, got)
			}
		})
	}
}

func TestAddr(t *testing.T) {
	cfg := &Config{Port: "8080"}
	if got := cfg.Addr(); got != ":8080" {
		t.Errorf("Addr(): want :8080, got %q", got)
	}

	cfg.Port = "3000"
	if got := cfg.Addr(); got != ":3000" {
		t.Errorf("Addr(): want :3000, got %q", got)
	}
}
