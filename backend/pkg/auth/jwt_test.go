package auth

import (
	"strings"
	"testing"
	"time"
)

const testSecret = "test-secret-must-be-at-least-32-bytes-long"

func TestGenerateAccessToken_RoundtripParse(t *testing.T) {
	userID := "5f9b1c5d-1234-4d2c-8b7e-0011223344ff"
	tok, err := GenerateAccessToken(userID, testSecret, AccessTokenTTL)
	if err != nil {
		t.Fatalf("GenerateAccessToken error: %v", err)
	}
	if strings.Count(tok, ".") != 2 {
		t.Fatalf("expected JWS with 3 segments, got %q", tok)
	}

	claims, err := ParseAccessToken(tok, testSecret)
	if err != nil {
		t.Fatalf("ParseAccessToken error: %v", err)
	}
	if claims.UserID != userID {
		t.Fatalf("expected UserID=%s, got %s", userID, claims.UserID)
	}
	if claims.ExpiresAt <= time.Now().Unix() {
		t.Fatalf("expected exp in future, got %d (now=%d)", claims.ExpiresAt, time.Now().Unix())
	}
}

func TestParseAccessToken_ExpiredToken(t *testing.T) {
	tok, err := GenerateAccessToken("user-1", testSecret, -1*time.Minute)
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}
	if _, err := ParseAccessToken(tok, testSecret); err == nil {
		t.Fatalf("expected error for expired token, got nil")
	}
}

func TestParseAccessToken_BadSignature(t *testing.T) {
	tok, err := GenerateAccessToken("user-1", testSecret, AccessTokenTTL)
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}
	if _, err := ParseAccessToken(tok, "wrong-secret-which-is-also-32+chars"); err == nil {
		t.Fatalf("expected signature error, got nil")
	}
}

func TestParseAccessToken_MalformedToken(t *testing.T) {
	if _, err := ParseAccessToken("not.a.jwt", testSecret); err == nil {
		t.Fatalf("expected error for malformed token, got nil")
	}
}
