package auth

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type errResponse struct {
	err    error
	status int
	msg    string
}

func respondError(c echo.Context, err error, mappings []errResponse, defaultMsg string) error {
	for _, m := range mappings {
		if errors.Is(err, m.err) {
			return web.JSONError(c, m.status, m.msg)
		}
	}
	c.Logger().Error(err)
	return web.JSONError(c, http.StatusInternalServerError, defaultMsg)
}

type RegisterRequest struct {
	Email    string `json:"email"    validate:"required,email"`
	Password string `json:"password" validate:"required,min=8"`
	Name     string `json:"name"     validate:"required,min=1,max=100"`
}

type LoginRequest struct {
	Email    string `json:"email"    validate:"required,email"`
	Password string `json:"password" validate:"required"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

type UserResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
}

type AuthResponse struct {
	User         *UserResponse        `json:"user"`
	AccessToken  string               `json:"access_token"`
	RefreshToken string               `json:"refresh_token"`
	Settings     dto.SettingsResponse `json:"settings"`
}

type RefreshResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type Handler struct {
	svc         *Service
	rateLimiter *AuthRateLimiter
}

func NewHandler(svc *Service, limiter ...*AuthRateLimiter) *Handler {
	rateLimiter := NewAuthRateLimiter()
	if len(limiter) > 0 && limiter[0] != nil {
		rateLimiter = limiter[0]
	}
	return &Handler{svc: svc, rateLimiter: rateLimiter}
}

func buildAuthResponse(session *SessionData, access, refresh string) AuthResponse {
	resp := AuthResponse{
		User: &UserResponse{
			ID:    uid.UUIDToString(session.User.ID),
			Email: session.User.Email,
			Name:  session.User.Name,
		},
		AccessToken:  access,
		RefreshToken: refresh,
		Settings:     session.Settings,
	}
	return resp
}

func (h *Handler) Register(c echo.Context) error {
	if !h.allow(c, "register", requestIdentifier(c, "email")) {
		return web.JSONError(c, http.StatusTooManyRequests, "too many authentication attempts")
	}
	var req RegisterRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	session, access, refresh, err := h.svc.Register(c.Request().Context(), req.Email, req.Password, req.Name)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrEmailInUse, http.StatusConflict, "email already in use"},
		}, "registration failed")
	}

	return c.JSON(http.StatusCreated, buildAuthResponse(session, access, refresh))
}

func (h *Handler) Login(c echo.Context) error {
	if !h.allow(c, "login", requestIdentifier(c, "email")) {
		return web.JSONError(c, http.StatusTooManyRequests, "too many authentication attempts")
	}
	var req LoginRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	session, access, refresh, err := h.svc.Login(c.Request().Context(), req.Email, req.Password)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrInvalidCredentials, http.StatusUnauthorized, "invalid credentials"},
		}, "login failed")
	}

	return c.JSON(http.StatusOK, buildAuthResponse(session, access, refresh))
}

func (h *Handler) Refresh(c echo.Context) error {
	if !h.allow(c, "refresh", requestIdentifier(c, "refresh_token")) {
		return web.JSONError(c, http.StatusTooManyRequests, "too many authentication attempts")
	}
	var req RefreshRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	access, refresh, err := h.svc.Refresh(c.Request().Context(), req.RefreshToken)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrInvalidRefreshToken, http.StatusUnauthorized, "invalid refresh token"},
			{ErrRefreshTokenReuse, http.StatusUnauthorized, "invalid refresh token"},
		}, "refresh failed")
	}

	return c.JSON(http.StatusOK, RefreshResponse{AccessToken: access, RefreshToken: refresh})
}

func (h *Handler) allow(c echo.Context, endpoint, identifier string) bool {
	return h.rateLimiter.Allow(endpoint, c.RealIP(), identifier)
}

func requestIdentifier(c echo.Context, field string) string {
	body, err := io.ReadAll(c.Request().Body)
	if err != nil {
		return ""
	}
	c.Request().Body = io.NopCloser(bytes.NewReader(body))

	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return ""
	}
	value, ok := payload[field].(string)
	if !ok {
		return ""
	}
	value = strings.TrimSpace(strings.ToLower(value))
	if field == "refresh_token" && value != "" {
		digest := sha256.Sum256([]byte(value))
		return hex.EncodeToString(digest[:])
	}
	return value
}

func (h *Handler) Logout(c echo.Context) error {
	var req LogoutRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	if err := h.svc.Logout(c.Request().Context(), req.RefreshToken); err != nil {
		return respondError(c, err, nil, "logout failed")
	}
	return c.NoContent(http.StatusNoContent)
}

// RevokeAllSessions invalidates all sessions for the authenticated account.
// The account comes from JWT middleware, never from request input.
func (h *Handler) RevokeAllSessions(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return web.JSONError(c, http.StatusUnauthorized, "missing authenticated user")
	}
	if err := h.svc.RevokeAllSessions(c.Request().Context(), userID); err != nil {
		return respondError(c, err, nil, "could not revoke sessions")
	}
	return c.NoContent(http.StatusNoContent)
}
