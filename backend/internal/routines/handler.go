package routines

import (
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
)

type UpdateRoutineRequest struct {
	CronExpr *string `json:"cron_expr"`
	Enabled  *bool   `json:"enabled"`
}

type TestRoutineResponse struct {
	Content string `json:"content"`
}

type Handler struct {
	svc *Service
	v   *validator.Validate
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) List(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	routines, err := h.svc.GetRoutines(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get routines"})
	}
	return c.JSON(http.StatusOK, routines)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid routine id"})
	}

	var req UpdateRoutineRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	routine, err := h.svc.UpdateRoutine(c.Request().Context(), id, userID, req.CronExpr, req.Enabled)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update routine"})
	}

	return c.JSON(http.StatusOK, routine)
}

func (h *Handler) Logs(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	// Use limit/offset in real app
	logs, err := h.svc.GetRoutineLogs(c.Request().Context(), userID, 50, 0)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get logs"})
	}
	return c.JSON(http.StatusOK, logs)
}

func (h *Handler) TestDaily(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	content, err := h.svc.TestRoutine(c.Request().Context(), userID, "daily")
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to test daily routine"})
	}
	return c.JSON(http.StatusOK, TestRoutineResponse{Content: content})
}

func (h *Handler) TestWeekly(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	content, err := h.svc.TestRoutine(c.Request().Context(), userID, "weekly")
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to test weekly routine"})
	}
	return c.JSON(http.StatusOK, TestRoutineResponse{Content: content})
}

func RegisterRoutes(api *echo.Group, h *Handler) {
	r := api.Group("/routines")
	r.GET("", h.List)
	r.GET("/logs", h.Logs)
	r.PATCH("/:id", h.Update)
	r.POST("/daily/test", h.TestDaily)
	r.POST("/weekly/test", h.TestWeekly)
}
