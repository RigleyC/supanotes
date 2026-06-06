package auth

import (
	"errors"
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

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
	svc *Service
	v   *validator.Validate
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) Register(c echo.Context) error {
	var req RegisterRequest
	if err := c.Bind(&req); err != nil {
		return jsonError(c, http.StatusBadRequest, "invalid request body")
	}
	if err := h.v.Struct(req); err != nil {
		return jsonError(c, http.StatusBadRequest, validationMessage(err))
	}

	user, access, refresh, err := h.svc.Register(c.Request().Context(), req.Email, req.Password, req.Name)
	if err != nil {
		if errors.Is(err, ErrEmailInUse) {
			return jsonError(c, http.StatusConflict, "email already in use")
		}
		c.Logger().Error(err)
		return jsonError(c, http.StatusInternalServerError, "registration failed")
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
	if err := c.Bind(&req); err != nil {
		return jsonError(c, http.StatusBadRequest, "invalid request body")
	}
	if err := h.v.Struct(req); err != nil {
		return jsonError(c, http.StatusBadRequest, validationMessage(err))
	}

	user, access, refresh, err := h.svc.Login(c.Request().Context(), req.Email, req.Password)
	if err != nil {
		if errors.Is(err, ErrInvalidCredentials) {
			return jsonError(c, http.StatusUnauthorized, "invalid credentials")
		}
		c.Logger().Error(err)
		return jsonError(c, http.StatusInternalServerError, "login failed")
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
	if err := c.Bind(&req); err != nil {
		return jsonError(c, http.StatusBadRequest, "invalid request body")
	}
	if err := h.v.Struct(req); err != nil {
		return jsonError(c, http.StatusBadRequest, validationMessage(err))
	}

	access, refresh, err := h.svc.Refresh(c.Request().Context(), req.RefreshToken)
	if err != nil {
		if errors.Is(err, ErrInvalidRefreshToken) {
			return jsonError(c, http.StatusUnauthorized, "invalid refresh token")
		}
		c.Logger().Error(err)
		return jsonError(c, http.StatusInternalServerError, "refresh failed")
	}

	return c.JSON(http.StatusOK, RefreshResponse{AccessToken: access, RefreshToken: refresh})
}

func (h *Handler) Logout(c echo.Context) error {
	var req LogoutRequest
	if err := c.Bind(&req); err != nil {
		return jsonError(c, http.StatusBadRequest, "invalid request body")
	}
	if err := h.v.Struct(req); err != nil {
		return jsonError(c, http.StatusBadRequest, validationMessage(err))
	}

	if err := h.svc.Logout(c.Request().Context(), req.RefreshToken); err != nil {
		c.Logger().Error(err)
		return jsonError(c, http.StatusInternalServerError, "logout failed")
	}
	return c.NoContent(http.StatusNoContent)
}

func jsonError(c echo.Context, status int, msg string) error {
	return c.JSON(status, map[string]string{"error": msg})
}

func validationMessage(err error) string {
	var verrs validator.ValidationErrors
	if errors.As(err, &verrs) && len(verrs) > 0 {
		e := verrs[0]
		return e.Field() + " failed " + e.Tag() + " validation"
	}
	return "validation failed"
}
