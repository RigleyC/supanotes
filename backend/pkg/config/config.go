package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

const devJWTSecret = "dev-only-jwt-secret-change-me-in-production-32+chars"
const devShareLinkSecret = "dev-only-share-link-secret-change-me-in-production-32+chars"

type Config struct {
	Port                          string
	DatabaseURL                   string
	JWTSecret                     string
	ShareLinkSecret               string
	PublicBaseURL                 string
	AppleTeamID                   string
	AndroidSHA256CertFingerprints []string
	JWTIssuer                     string
	JWTAudience                   string
	CORSOrigins                   []string
	Environment                   string
	EnableDebugEndpoints          bool
	AlexaApplicationID            string
	AlexaClientID                 string
	AlexaClientSecret             string
	AlexaRedirectURIs             []string

	// Storage (S3-compatible: AWS, MinIO, Supabase, GCS)
	S3Endpoint        string // S3_ENDPOINT — e.g. https://s3.amazonaws.com or http://minio:9000
	S3Region          string // S3_REGION
	S3Bucket          string // S3_BUCKET
	S3AccessKeyID     string // S3_ACCESS_KEY_ID
	S3SecretAccessKey string // S3_SECRET_ACCESS_KEY
}

func Load() (*Config, error) {
	_ = godotenv.Load()

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}

	env := strings.ToLower(strings.TrimSpace(os.Getenv("ENVIRONMENT")))
	if env == "" {
		return nil, fmt.Errorf("config: ENVIRONMENT is required; set ENVIRONMENT=dev for local development")
	}
	enableDebugEndpoints, err := parseBoolEnv("ENABLE_DEBUG_ENDPOINTS")
	if err != nil {
		return nil, err
	}
	if enableDebugEndpoints && env != "dev" {
		return nil, fmt.Errorf("config: ENABLE_DEBUG_ENDPOINTS is only allowed with ENVIRONMENT=dev")
	}

	jwtSecret := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if jwtSecret == "" {
		if env != "dev" {
			return nil, fmt.Errorf("config: JWT_SECRET is required outside dev")
		}
		jwtSecret = devJWTSecret
	}
	if len([]byte(jwtSecret)) < 32 {
		return nil, fmt.Errorf("config: JWT_SECRET must contain at least 32 bytes")
	}
	jwtIssuer := firstNonEmpty(strings.TrimSpace(os.Getenv("JWT_ISSUER")), "supanotes-api")
	jwtAudience := firstNonEmpty(strings.TrimSpace(os.Getenv("JWT_AUDIENCE")), "supanotes-client")
	shareLinkSecret := strings.TrimSpace(os.Getenv("SHARE_LINK_SECRET"))
	if shareLinkSecret == "" {
		if env != "dev" {
			return nil, fmt.Errorf("config: SHARE_LINK_SECRET is required outside dev")
		}
		shareLinkSecret = devShareLinkSecret
	}
	if len([]byte(shareLinkSecret)) < 32 {
		return nil, fmt.Errorf("config: SHARE_LINK_SECRET must contain at least 32 bytes")
	}
	publicBaseURL := strings.TrimRight(strings.TrimSpace(os.Getenv("PUBLIC_BASE_URL")), "/")
	if publicBaseURL == "" {
		if env != "dev" {
			return nil, fmt.Errorf("config: PUBLIC_BASE_URL is required outside dev")
		}
		publicBaseURL = "http://localhost:8080"
	}
	appleTeamID := strings.TrimSpace(os.Getenv("IOS_TEAM_ID"))
	androidSHA256CertFingerprints := parseList(os.Getenv("ANDROID_SHA256_CERT"))

	corsOrigins := parseCORSOrigins(os.Getenv("CORS_ORIGINS"), env)

	alexaApplicationID := strings.TrimSpace(os.Getenv("ALEXA_APPLICATION_ID"))
	alexaClientID := strings.TrimSpace(os.Getenv("ALEXA_CLIENT_ID"))
	alexaClientSecret := strings.TrimSpace(os.Getenv("ALEXA_CLIENT_SECRET"))
	alexaRedirectURIs := parseList(os.Getenv("ALEXA_REDIRECT_URIS"))
	if err := validateAlexaConfig(env, alexaApplicationID, alexaClientID, alexaClientSecret, alexaRedirectURIs); err != nil {
		return nil, err
	}

	return &Config{
		Port:                          port,
		Environment:                   env,
		EnableDebugEndpoints:          enableDebugEndpoints,
		AlexaApplicationID:            alexaApplicationID,
		AlexaClientID:                 alexaClientID,
		AlexaClientSecret:             alexaClientSecret,
		AlexaRedirectURIs:             alexaRedirectURIs,
		DatabaseURL:                   os.Getenv("DATABASE_URL"),
		JWTSecret:                     jwtSecret,
		ShareLinkSecret:               shareLinkSecret,
		PublicBaseURL:                 publicBaseURL,
		AppleTeamID:                   appleTeamID,
		AndroidSHA256CertFingerprints: androidSHA256CertFingerprints,
		JWTIssuer:                     jwtIssuer,
		JWTAudience:                   jwtAudience,
		CORSOrigins:                   corsOrigins,
		S3Endpoint:                    firstNonEmpty(os.Getenv("S3_ENDPOINT"), os.Getenv("AWS_ENDPOINT_URL_S3")),
		S3Region:                      firstNonEmpty(os.Getenv("S3_REGION"), os.Getenv("AWS_REGION")),
		S3Bucket:                      firstNonEmpty(os.Getenv("S3_BUCKET"), os.Getenv("BUCKET_NAME")),
		S3AccessKeyID:                 firstNonEmpty(os.Getenv("S3_ACCESS_KEY_ID"), os.Getenv("AWS_ACCESS_KEY_ID")),
		S3SecretAccessKey:             firstNonEmpty(os.Getenv("S3_SECRET_ACCESS_KEY"), os.Getenv("AWS_SECRET_ACCESS_KEY")),
	}, nil
}

func (c *Config) IsDev() bool {
	return strings.EqualFold(c.Environment, "dev")
}

func (c *Config) AlexaConfigured() bool {
	return c.AlexaApplicationID != "" && c.AlexaClientID != "" && c.AlexaClientSecret != "" && len(c.AlexaRedirectURIs) > 0
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

func parseList(raw string) []string {
	parts := strings.Split(raw, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if value := strings.TrimSpace(part); value != "" {
			result = append(result, value)
		}
	}
	return result
}

func parseBoolEnv(name string) (bool, error) {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return false, nil
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, fmt.Errorf("config: %s must be a boolean", name)
	}
	return value, nil
}

func validateAlexaConfig(env, applicationID, clientID, clientSecret string, redirectURIs []string) error {
	configured := applicationID != "" || clientID != "" || clientSecret != "" || len(redirectURIs) > 0
	if !configured {
		return nil
	}
	if applicationID == "" || clientID == "" || clientSecret == "" || len(redirectURIs) == 0 {
		if env == "dev" {
			return nil
		}
		return fmt.Errorf("config: Alexa configuration must include ALEXA_APPLICATION_ID, ALEXA_CLIENT_ID, ALEXA_CLIENT_SECRET and ALEXA_REDIRECT_URIS")
	}
	return nil
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
