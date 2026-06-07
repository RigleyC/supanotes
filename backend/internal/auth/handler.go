package auth

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/onboarding"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

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
	svc           *Service
	onboardingSvc *onboarding.Service
}

func NewHandler(svc *Service, onboardingSvc *onboarding.Service) *Handler {
	return &Handler{
		svc:           svc,
		onboardingSvc: onboardingSvc,
	}
}

func (h *Handler) Register(c echo.Context) error {
	var req RegisterRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	user, access, refresh, err := h.svc.Register(c.Request().Context(), req.Email, req.Password, req.Name)
	if err != nil {
		if errors.Is(err, ErrEmailInUse) {
			return web.JSONError(c, http.StatusConflict, "email already in use")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "registration failed")
	}

	if h.onboardingSvc != nil {
		if err := h.onboardingSvc.OnboardUser(c.Request().Context(), user.ID); err != nil {
			c.Logger().Error(err)
			return web.JSONError(c, http.StatusInternalServerError, "registration failed")
		}
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
		if errors.Is(err, ErrInvalidCredentials) {
			return web.JSONError(c, http.StatusUnauthorized, "invalid credentials")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "login failed")
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
		if errors.Is(err, ErrInvalidRefreshToken) {
			return web.JSONError(c, http.StatusUnauthorized, "invalid refresh token")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "refresh failed")
	}

	return c.JSON(http.StatusOK, RefreshResponse{AccessToken: access, RefreshToken: refresh})
}

func (h *Handler) Logout(c echo.Context) error {
	var req LogoutRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	if err := h.svc.Logout(c.Request().Context(), req.RefreshToken); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "logout failed")
	}
	return c.NoContent(http.StatusNoContent)
}
