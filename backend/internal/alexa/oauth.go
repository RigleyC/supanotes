package alexa

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	internalauth "github.com/RigleyC/supanotes/internal/auth"
	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type OAuthHandler struct {
	auth        *internalauth.Service
	pool        *pgxpool.Pool
	cfg         *config.Config
	rateLimiter *internalauth.AuthRateLimiter
}

func NewOAuthHandler(authSvc *internalauth.Service, pool *pgxpool.Pool, cfg *config.Config, limiters ...*internalauth.AuthRateLimiter) *OAuthHandler {
	rateLimiter := internalauth.NewAuthRateLimiter()
	if len(limiters) > 0 && limiters[0] != nil {
		rateLimiter = limiters[0]
	}
	return &OAuthHandler{auth: authSvc, pool: pool, cfg: cfg, rateLimiter: rateLimiter}
}

func (h *OAuthHandler) Authorize(c echo.Context) error {
	q := c.QueryParams()
	if q.Get("client_id") != h.cfg.AlexaClientID || q.Get("response_type") != "code" || q.Get("state") == "" {
		return c.String(http.StatusBadRequest, "invalid OAuth authorization request")
	}
	redirectURI, err := h.validRedirect(q.Get("redirect_uri"))
	if err != nil {
		return c.String(http.StatusBadRequest, "invalid OAuth authorization request")
	}
	return c.HTML(http.StatusOK, fmt.Sprintf(`<!doctype html><meta name="viewport" content="width=device-width"><h1>Vincular Alexa ao SupaNotes</h1><form method="post"><input type="hidden" name="client_id" value="%s"><input type="hidden" name="redirect_uri" value="%s"><input type="hidden" name="state" value="%s"><label>E-mail<br><input name="email" type="email" required></label><br><label>Senha<br><input name="password" type="password" required></label><br><button type="submit">Vincular conta</button></form>`, template.HTMLEscapeString(q.Get("client_id")), template.HTMLEscapeString(redirectURI), template.HTMLEscapeString(q.Get("state"))))
}

func (h *OAuthHandler) AuthorizeSubmit(c echo.Context) error {
	if c.FormValue("client_id") != h.cfg.AlexaClientID {
		return c.String(http.StatusBadRequest, "invalid client")
	}
	redirectURI, err := h.validRedirect(c.FormValue("redirect_uri"))
	if err != nil {
		return c.String(http.StatusBadRequest, err.Error())
	}
	email := strings.ToLower(strings.TrimSpace(c.FormValue("email")))
	if !h.rateLimiter.Allow("alexa_authorize", c.RealIP(), email) {
		return c.String(http.StatusTooManyRequests, "muitas tentativas; tente novamente mais tarde")
	}
	session, _, _, err := h.auth.Login(c.Request().Context(), email, c.FormValue("password"))
	if err != nil {
		return c.String(http.StatusUnauthorized, "e-mail ou senha inválidos")
	}
	code, err := randomCode()
	if err != nil {
		return err
	}
	hash := hashCode(code)
	_, err = h.pool.Exec(c.Request().Context(), `INSERT INTO alexa_authorization_codes (code_hash,user_id,client_id,redirect_uri,expires_at) VALUES ($1,$2,$3,$4,$5)`, hash, session.User.ID, h.cfg.AlexaClientID, redirectURI, time.Now().Add(5*time.Minute))
	if err != nil {
		return err
	}
	return c.Redirect(http.StatusFound, redirectURI+"?code="+url.QueryEscape(code)+"&state="+url.QueryEscape(c.FormValue("state")))
}

func (h *OAuthHandler) Token(c echo.Context) error {
	clientID, clientSecret := c.FormValue("client_id"), c.FormValue("client_secret")
	if basicID, basicSecret, ok := c.Request().BasicAuth(); ok {
		clientID, clientSecret = basicID, basicSecret
	}
	if clientID != h.cfg.AlexaClientID || clientSecret != h.cfg.AlexaClientSecret {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid_client"})
	}
	if c.FormValue("grant_type") == "refresh_token" {
		return h.refresh(c)
	}
	if c.FormValue("grant_type") != "authorization_code" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "unsupported_grant_type"})
	}
	redirectURI, err := h.validRedirect(c.FormValue("redirect_uri"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_request"})
	}
	var userID pgtype.UUID
	refreshToken, err := randomCode()
	if err != nil {
		return err
	}
	refreshExpiry := time.Now().Add(90 * 24 * time.Hour)
	err = h.pool.QueryRow(c.Request().Context(), `UPDATE alexa_authorization_codes SET used_at=NOW(),refresh_token_hash=$3,refresh_expires_at=$4 WHERE code_hash=$1 AND client_id=$2 AND redirect_uri=$5 AND used_at IS NULL AND expires_at > NOW() RETURNING user_id`, hashCode(c.FormValue("code")), h.cfg.AlexaClientID, hashCode(refreshToken), refreshExpiry, redirectURI).Scan(&userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_grant"})
		}
		return err
	}
	access, err := authpkg.GenerateAccessToken(
		uid.UUIDToString(userID),
		h.cfg.JWTSecret,
		authpkg.AccessTokenTTL,
		authpkg.TokenOptions{Issuer: h.cfg.JWTIssuer, Audience: h.cfg.JWTAudience},
	)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]any{"access_token": access, "token_type": "Bearer", "expires_in": int(authpkg.AccessTokenTTL.Seconds()), "refresh_token": refreshToken})
}

func (h *OAuthHandler) refresh(c echo.Context) error {
	var userID pgtype.UUID
	newRefresh, err := randomCode()
	if err != nil {
		return err
	}
	oldHash := hashCode(c.FormValue("refresh_token"))
	err = h.pool.QueryRow(c.Request().Context(), `
		UPDATE alexa_authorization_codes
		SET previous_refresh_token_hash=refresh_token_hash,
		    refresh_token_hash=$2,
		    refresh_expires_at=$3
		WHERE refresh_token_hash=$1
		  AND refresh_expires_at > NOW()
		  AND refresh_revoked_at IS NULL
		RETURNING user_id`, oldHash, hashCode(newRefresh), time.Now().Add(90*24*time.Hour)).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		_, revokeErr := h.pool.Exec(c.Request().Context(), `
			UPDATE alexa_authorization_codes
			SET refresh_revoked_at=NOW()
			WHERE previous_refresh_token_hash=$1
			  AND refresh_revoked_at IS NULL`, oldHash)
		if revokeErr != nil {
			return revokeErr
		}
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_grant"})
	}
	if err != nil {
		return err
	}
	access, err := authpkg.GenerateAccessToken(
		uid.UUIDToString(userID),
		h.cfg.JWTSecret,
		authpkg.AccessTokenTTL,
		authpkg.TokenOptions{Issuer: h.cfg.JWTIssuer, Audience: h.cfg.JWTAudience},
	)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]any{"access_token": access, "token_type": "Bearer", "expires_in": int(authpkg.AccessTokenTTL.Seconds()), "refresh_token": newRefresh})
}

func (h *OAuthHandler) validRedirect(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil {
		return "", errors.New("invalid redirect_uri")
	}
	for _, allowed := range h.cfg.AlexaRedirectURIs {
		if raw == allowed {
			return raw, nil
		}
	}
	return "", errors.New("invalid redirect_uri")
}
func randomCode() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
func hashCode(s string) string {
	h := sha256.Sum256([]byte(s))
	return base64.RawURLEncoding.EncodeToString(h[:])
}
