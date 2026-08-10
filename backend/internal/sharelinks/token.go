package sharelinks

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
)

var ErrInvalidToken = errors.New("invalid share link token")

type TokenSigner struct {
	secret []byte
}

func NewTokenSigner(secret string) TokenSigner {
	return TokenSigner{secret: []byte(secret)}
}

func (s TokenSigner) Sign(id uuid.UUID) (string, error) {
	if len(s.secret) == 0 {
		return "", errors.New("share link signing secret is empty")
	}
	payload := id.String()
	mac := hmac.New(sha256.New, s.secret)
	_, _ = mac.Write([]byte(payload))
	signature := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return payload + "." + signature, nil
}

func (s TokenSigner) Verify(token string) (uuid.UUID, error) {
	if len(s.secret) == 0 {
		return uuid.Nil, ErrInvalidToken
	}
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return uuid.Nil, ErrInvalidToken
	}
	id, err := uuid.Parse(parts[0])
	if err != nil {
		return uuid.Nil, ErrInvalidToken
	}
	supplied, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return uuid.Nil, ErrInvalidToken
	}
	mac := hmac.New(sha256.New, s.secret)
	_, _ = mac.Write([]byte(id.String()))
	if !hmac.Equal(supplied, mac.Sum(nil)) {
		return uuid.Nil, ErrInvalidToken
	}
	return id, nil
}

func (s TokenSigner) String() string {
	return fmt.Sprintf("TokenSigner(secretSet=%t)", len(s.secret) > 0)
}
