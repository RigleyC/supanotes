package sharelinks

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestTokenSignerRoundTrip(t *testing.T) {
	signer := NewTokenSigner("share-link-test-secret")
	tokenID := uuid.New()

	token, err := signer.Sign(tokenID)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}

	got, err := signer.Verify(token)
	if err != nil {
		t.Fatalf("verify token: %v", err)
	}
	if got != tokenID {
		t.Fatalf("token id: got %s, want %s", got, tokenID)
	}
}

func TestTokenSignerRejectsTampering(t *testing.T) {
	signer := NewTokenSigner("share-link-test-secret")
	token, err := signer.Sign(uuid.New())
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}

	replacement := byte('a')
	separator := strings.IndexByte(token, '.')
	tampered := token[:separator+1] + string(replacement) + token[separator+2:]
	if _, err := signer.Verify(tampered); err == nil {
		t.Fatal("expected tampered token to be rejected")
	}
}
