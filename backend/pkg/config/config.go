package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/joho/godotenv"
)

const devJWTSecret = "dev-only-jwt-secret-change-me-in-production-32+chars"

type Config struct {
	Port        string
	DatabaseURL string
	JWTSecret   string
	CORSOrigins []string
	Environment string

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
		Port:              port,
		Environment:       env,
		DatabaseURL:       os.Getenv("DATABASE_URL"),
		JWTSecret:         jwtSecret,
		CORSOrigins:       corsOrigins,
		S3Endpoint:        firstNonEmpty(os.Getenv("S3_ENDPOINT"), os.Getenv("AWS_ENDPOINT_URL_S3")),
		S3Region:          firstNonEmpty(os.Getenv("S3_REGION"), os.Getenv("AWS_REGION")),
		S3Bucket:          firstNonEmpty(os.Getenv("S3_BUCKET"), os.Getenv("BUCKET_NAME")),
		S3AccessKeyID:     firstNonEmpty(os.Getenv("S3_ACCESS_KEY_ID"), os.Getenv("AWS_ACCESS_KEY_ID")),
		S3SecretAccessKey: firstNonEmpty(os.Getenv("S3_SECRET_ACCESS_KEY"), os.Getenv("AWS_SECRET_ACCESS_KEY")),
		S3PublicBaseURL:   firstNonEmpty(os.Getenv("S3_PUBLIC_BASE_URL"), buildTigrisPublicBaseURL(firstNonEmpty(os.Getenv("S3_BUCKET"), os.Getenv("BUCKET_NAME")), firstNonEmpty(os.Getenv("S3_ENDPOINT"), os.Getenv("AWS_ENDPOINT_URL_S3")))),
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
