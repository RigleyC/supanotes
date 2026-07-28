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
	auth *internalauth.Service
	pool *pgxpool.Pool
	cfg  *config.Config
}

func NewOAuthHandler(authSvc *internalauth.Service, pool *pgxpool.Pool, cfg *config.Config) *OAuthHandler {
	return &OAuthHandler{auth: authSvc, pool: pool, cfg: cfg}
}

func (h *OAuthHandler) Authorize(c echo.Context) error {
	q := c.QueryParams()
	if q.Get("client_id") != h.cfg.AlexaClientID || q.Get("response_type") != "code" || q.Get("redirect_uri") == "" || q.Get("state") == "" {
		return c.String(http.StatusBadRequest, "invalid OAuth authorization request")
	}
	return c.HTML(http.StatusOK, fmt.Sprintf(`<!doctype html><meta name="viewport" content="width=device-width"><h1>Vincular Alexa ao SupaNotes</h1><form method="post"><input type="hidden" name="client_id" value="%s"><input type="hidden" name="redirect_uri" value="%s"><input type="hidden" name="state" value="%s"><label>E-mail<br><input name="email" type="email" required></label><br><label>Senha<br><input name="password" type="password" required></label><br><button type="submit">Vincular conta</button></form>`, template.HTMLEscapeString(q.Get("client_id")), template.HTMLEscapeString(q.Get("redirect_uri")), template.HTMLEscapeString(q.Get("state"))))
}

func (h *OAuthHandler) AuthorizeSubmit(c echo.Context) error {
	if c.FormValue("client_id") != h.cfg.AlexaClientID {
		return c.String(http.StatusBadRequest, "invalid client")
	}
	redirectURI, err := validRedirect(c.FormValue("redirect_uri"))
	if err != nil {
		return c.String(http.StatusBadRequest, err.Error())
	}
	session, _, _, err := h.auth.Login(c.Request().Context(), c.FormValue("email"), c.FormValue("password"))
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
	redirectURI, err := validRedirect(c.FormValue("redirect_uri"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_request"})
	}
	var codeHash string
	var userID pgtype.UUID
	var storedRedirect string
	var expires time.Time
	err = h.pool.QueryRow(c.Request().Context(), `SELECT code_hash,user_id,redirect_uri,expires_at FROM alexa_authorization_codes WHERE code_hash=$1 AND client_id=$2 AND used_at IS NULL`, hashCode(c.FormValue("code")), h.cfg.AlexaClientID).Scan(&codeHash, &userID, &storedRedirect, &expires)
	if errors.Is(err, pgx.ErrNoRows) || err != nil || storedRedirect != redirectURI || time.Now().After(expires) {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_grant"})
	}
	refreshToken, err := randomCode()
	if err != nil {
		return err
	}
	refreshExpiry := time.Now().Add(90 * 24 * time.Hour)
	if _, err = h.pool.Exec(c.Request().Context(), `UPDATE alexa_authorization_codes SET used_at=NOW(),refresh_token_hash=$2,refresh_expires_at=$3 WHERE code_hash=$1 AND used_at IS NULL`, codeHash, hashCode(refreshToken), refreshExpiry); err != nil {
		return err
	}
	access, err := authpkg.GenerateAccessToken(uid.UUIDToString(userID), h.cfg.JWTSecret, authpkg.AccessTokenTTL)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]any{"access_token": access, "token_type": "Bearer", "expires_in": int(authpkg.AccessTokenTTL.Seconds()), "refresh_token": refreshToken})
}

func (h *OAuthHandler) refresh(c echo.Context) error {
	var userID pgtype.UUID
	var refreshExpiry time.Time
	var codeHash string
	err := h.pool.QueryRow(c.Request().Context(), `SELECT user_id,refresh_expires_at,refresh_token_hash FROM alexa_authorization_codes WHERE refresh_token_hash=$1`, hashCode(c.FormValue("refresh_token"))).Scan(&userID, &refreshExpiry, &codeHash)
	if errors.Is(err, pgx.ErrNoRows) || err != nil || time.Now().After(refreshExpiry) {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid_grant"})
	}
	newRefresh, err := randomCode()
	if err != nil {
		return err
	}
	_, err = h.pool.Exec(c.Request().Context(), `UPDATE alexa_authorization_codes SET refresh_token_hash=$2,refresh_expires_at=$3 WHERE code_hash=$1 AND refresh_token_hash=$4`, codeHash, hashCode(newRefresh), time.Now().Add(90*24*time.Hour), hashCode(c.FormValue("refresh_token")))
	if err != nil {
		return err
	}
	access, err := authpkg.GenerateAccessToken(uid.UUIDToString(userID), h.cfg.JWTSecret, authpkg.AccessTokenTTL)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]any{"access_token": access, "token_type": "Bearer", "expires_in": int(authpkg.AccessTokenTTL.Seconds()), "refresh_token": newRefresh})
}

func validRedirect(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return "", errors.New("invalid redirect_uri")
	}
	return raw, nil
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
