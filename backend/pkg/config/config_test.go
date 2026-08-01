package config

import (
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	for _, k := range []string{"PORT", "ENVIRONMENT", "DATABASE_URL", "JWT_SECRET", "JWT_ISSUER", "JWT_AUDIENCE", "ALEXA_REDIRECT_URIS"} {
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
	if cfg.JWTSecret == "" {
		t.Errorf("JWTSecret: want dev fallback in dev mode, got empty")
	}
	if cfg.JWTIssuer != "supanotes-api" || cfg.JWTAudience != "supanotes-client" {
		t.Errorf("JWT claims defaults: issuer=%q audience=%q", cfg.JWTIssuer, cfg.JWTAudience)
	}
	if len(cfg.AlexaRedirectURIs) != 0 {
		t.Errorf("AlexaRedirectURIs: want empty by default, got %v", cfg.AlexaRedirectURIs)
	}
}

func TestLoad_FromEnv(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("ENVIRONMENT", "prod")
	t.Setenv("DATABASE_URL", "postgres://user:pass@db:5432/app?sslmode=disable")
	t.Setenv("JWT_SECRET", "prod-secret-at-least-32-characters-long")
	t.Setenv("JWT_ISSUER", "custom-api")
	t.Setenv("JWT_AUDIENCE", "custom-client")
	t.Setenv("ALEXA_REDIRECT_URIS", "https://example.com/one, https://example.com/two")

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
	if cfg.JWTSecret != "prod-secret-at-least-32-characters-long" {
		t.Errorf("JWTSecret mismatch: %q", cfg.JWTSecret)
	}
	if cfg.JWTIssuer != "custom-api" || cfg.JWTAudience != "custom-client" {
		t.Errorf("JWT claims mismatch: issuer=%q audience=%q", cfg.JWTIssuer, cfg.JWTAudience)
	}
	if len(cfg.AlexaRedirectURIs) != 2 || cfg.AlexaRedirectURIs[0] != "https://example.com/one" || cfg.AlexaRedirectURIs[1] != "https://example.com/two" {
		t.Errorf("AlexaRedirectURIs mismatch: %v", cfg.AlexaRedirectURIs)
	}
}

func TestLoad_ProdRequiresJWTSecret(t *testing.T) {
	for _, k := range []string{"PORT", "ENVIRONMENT", "DATABASE_URL", "JWT_SECRET", "JWT_ISSUER", "JWT_AUDIENCE", "ALEXA_REDIRECT_URIS"} {
		t.Setenv(k, "")
	}
	t.Setenv("ENVIRONMENT", "prod")

	if _, err := Load(); err == nil {
		t.Fatal("Load() in prod with no JWT_SECRET: want error, got nil")
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
