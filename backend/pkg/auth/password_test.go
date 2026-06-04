package auth

import (
	"strings"
	"testing"
)

func TestHashPassword_ProducesArgon2idEncoded(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword returned error: %v", err)
	}
	if !strings.HasPrefix(hash, "$argon2id$") {
		t.Fatalf("expected hash to start with $argon2id$, got %q", hash)
	}
	parts := strings.Split(hash, "$")
	if len(parts) != 6 {
		t.Fatalf("expected 6 segments in encoded hash, got %d (%q)", len(parts), hash)
	}
}

func TestHashPassword_DifferentSaltsProduceDifferentHashes(t *testing.T) {
	plain := "another-password-123"
	h1, err := HashPassword(plain)
	if err != nil {
		t.Fatalf("hash 1 error: %v", err)
	}
	h2, err := HashPassword(plain)
	if err != nil {
		t.Fatalf("hash 2 error: %v", err)
	}
	if h1 == h2 {
		t.Fatalf("expected different hashes due to random salt, both = %q", h1)
	}
}

func TestVerifyPassword_CorrectPassword(t *testing.T) {
	plain := "my-very-secret-password"
	hash, err := HashPassword(plain)
	if err != nil {
		t.Fatalf("HashPassword error: %v", err)
	}
	ok, err := VerifyPassword(plain, hash)
	if err != nil {
		t.Fatalf("VerifyPassword error: %v", err)
	}
	if !ok {
		t.Fatalf("expected password to verify, got false")
	}
}

func TestVerifyPassword_WrongPassword(t *testing.T) {
	hash, err := HashPassword("right-password")
	if err != nil {
		t.Fatalf("HashPassword error: %v", err)
	}
	ok, err := VerifyPassword("wrong-password", hash)
	if err != nil {
		t.Fatalf("VerifyPassword error: %v", err)
	}
	if ok {
		t.Fatalf("expected wrong password to fail verification, got true")
	}
}

func TestVerifyPassword_MalformedEncoded(t *testing.T) {
	cases := []string{
		"",
		"not-an-argon2-hash",
		"$argon2id$v=19$only-two-segments",
		"$argon2id$v=19$m=65536,t=1,p=4$!!!!$!!!!",
	}
	for _, c := range cases {
		if _, err := VerifyPassword("anything", c); err == nil {
			t.Fatalf("expected error for malformed encoded %q, got nil", c)
		}
	}
}
