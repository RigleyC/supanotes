package auth

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

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
	User         *UserResponse `json:"user"`
	AccessToken  string        `json:"access_token"`
	RefreshToken string        `json:"refresh_token"`
}

type RefreshResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Register(c echo.Context) error {
	var req RegisterRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	user, access, refresh, err := h.svc.Register(c.Request().Context(), req.Email, req.Password, req.Name)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrEmailInUse, http.StatusConflict, "email already in use"},
		}, "registration failed")
	}

	return c.JSON(http.StatusCreated, AuthResponse{
		User: &UserResponse{
			ID:    uid.UUIDToString(user.ID),
			Email: user.Email,
			Name:  user.Name,
		},
		AccessToken:  access,
		RefreshToken: refresh,
	})
}

func (h *Handler) Login(c echo.Context) error {
	var req LoginRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	user, access, refresh, err := h.svc.Login(c.Request().Context(), req.Email, req.Password)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrInvalidCredentials, http.StatusUnauthorized, "invalid credentials"},
		}, "login failed")
	}

	return c.JSON(http.StatusOK, AuthResponse{
		User: &UserResponse{
			ID:    uid.UUIDToString(user.ID),
			Email: user.Email,
			Name:  user.Name,
		},
		AccessToken:  access,
		RefreshToken: refresh,
	})
}

func (h *Handler) Refresh(c echo.Context) error {
	var req RefreshRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	access, refresh, err := h.svc.Refresh(c.Request().Context(), req.RefreshToken)
	if err != nil {
		return respondError(c, err, []errResponse{
			{ErrInvalidRefreshToken, http.StatusUnauthorized, "invalid refresh token"},
		}, "refresh failed")
	}

	return c.JSON(http.StatusOK, RefreshResponse{AccessToken: access, RefreshToken: refresh})
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
