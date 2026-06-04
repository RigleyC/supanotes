package auth

import (
	"encoding/hex"
	"testing"
)

func TestGenerateRefreshToken_LengthAndHashMatch(t *testing.T) {
	plain, hash, err := GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken error: %v", err)
	}
	if len(plain) != 64 {
		t.Fatalf("expected plain token length 64 hex chars, got %d", len(plain))
	}
	if _, err := hex.DecodeString(plain); err != nil {
		t.Fatalf("plain token is not valid hex: %v", err)
	}
	if hash == "" || hash == plain {
		t.Fatalf("expected non-empty hash distinct from plain, got hash=%q plain=%q", hash, plain)
	}
	if HashRefreshToken(plain) != hash {
		t.Fatalf("HashRefreshToken(plain) != returned hash")
	}
}

func TestHashRefreshToken_Deterministic(t *testing.T) {
	plain := "deadbeefcafebabe"
	if HashRefreshToken(plain) != HashRefreshToken(plain) {
		t.Fatalf("hash should be deterministic")
	}
	if HashRefreshToken(plain) == HashRefreshToken("different") {
		t.Fatalf("different inputs should produce different hashes")
	}
}

func TestGenerateRefreshToken_TokensAreUnique(t *testing.T) {
	seen := make(map[string]struct{})
	for i := 0; i < 50; i++ {
		plain, _, err := GenerateRefreshToken()
		if err != nil {
			t.Fatalf("iter %d: %v", i, err)
		}
		if _, dup := seen[plain]; dup {
			t.Fatalf("duplicate token generated at iter %d", i)
		}
		seen[plain] = struct{}{}
	}
}
