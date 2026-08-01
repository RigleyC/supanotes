package auth

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	AccessTokenTTL  = 15 * time.Minute
	RefreshTokenTTL = 30 * 24 * time.Hour
)

var ErrInvalidToken = errors.New("auth: invalid token")

type Claims struct {
	UserID    string           `json:"sub"`
	ExpiresAt int64            `json:"exp"`
	IssuedAt  int64            `json:"iat"`
	Issuer    string           `json:"iss,omitempty"`
	Audience  jwt.ClaimStrings `json:"aud,omitempty"`
}

func (c Claims) GetExpirationTime() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(c.ExpiresAt, 0)), nil
}
func (c Claims) GetIssuedAt() (*jwt.NumericDate, error) {
	return jwt.NewNumericDate(time.Unix(c.IssuedAt, 0)), nil
}
func (c Claims) GetNotBefore() (*jwt.NumericDate, error) { return nil, nil }
func (c Claims) GetIssuer() (string, error)              { return c.Issuer, nil }
func (c Claims) GetSubject() (string, error)             { return c.UserID, nil }
func (c Claims) GetAudience() (jwt.ClaimStrings, error)  { return c.Audience, nil }

type TokenOptions struct {
	Issuer   string
	Audience string
}

func GenerateAccessToken(userID, secret string, ttl time.Duration, options TokenOptions) (string, error) {
	if secret == "" {
		return "", errors.New("auth: empty JWT secret")
	}
	now := time.Now()
	claims := Claims{
		UserID:    userID,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
	}
	if options.Issuer == "" || options.Audience == "" {
		return "", errors.New("auth: JWT issuer and audience are required")
	}
	claims.Issuer = options.Issuer
	claims.Audience = jwt.ClaimStrings{options.Audience}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := tok.SignedString([]byte(secret))
	if err != nil {
		return "", fmt.Errorf("auth: sign token: %w", err)
	}
	return signed, nil
}

func ParseAccessToken(tokenStr, secret string, options TokenOptions) (*Claims, error) {
	if secret == "" {
		return nil, errors.New("auth: empty JWT secret")
	}
	claims := &Claims{}
	parserOptions := []jwt.ParserOption{
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
	}
	if options.Issuer == "" || options.Audience == "" {
		return nil, errors.New("auth: JWT issuer and audience are required")
	}
	parserOptions = append(parserOptions, jwt.WithIssuer(options.Issuer), jwt.WithAudience(options.Audience))
	parsed, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
		if t.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("%w: unexpected signing method %v", ErrInvalidToken, t.Header["alg"])
		}
		return []byte(secret), nil
	}, parserOptions...)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	if !parsed.Valid {
		return nil, ErrInvalidToken
	}
	return claims, nil
}
