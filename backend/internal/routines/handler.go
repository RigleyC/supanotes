package routines

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/web"
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
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) List(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	routines, err := h.svc.GetRoutines(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get routines")
	}
	return c.JSON(http.StatusOK, routines)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid routine id")
	}

	var req UpdateRoutineRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	routine, err := h.svc.UpdateRoutine(c.Request().Context(), id, userID, req.CronExpr, req.Enabled)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update routine")
	}

	return c.JSON(http.StatusOK, routine)
}

func (h *Handler) Logs(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	// Use limit/offset in real app
	logs, err := h.svc.GetRoutineLogs(c.Request().Context(), userID, 50, 0)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get logs")
	}
	return c.JSON(http.StatusOK, logs)
}

func (h *Handler) testRoutine(c echo.Context, routineType string) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	content, err := h.svc.TestRoutine(c.Request().Context(), userID, routineType)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to test "+routineType+" routine")
	}
	return c.JSON(http.StatusOK, TestRoutineResponse{Content: content})
}

func (h *Handler) TestDaily(c echo.Context) error {
	return h.testRoutine(c, "daily")
}

func (h *Handler) TestWeekly(c echo.Context) error {
	return h.testRoutine(c, "weekly")
}

func RegisterRoutes(api *echo.Group, h *Handler) {
	r := api.Group("/routines")
	r.GET("", h.List)
	r.GET("/logs", h.Logs)
	r.PATCH("/:id", h.Update)
	r.POST("/daily/test", h.TestDaily)
	r.POST("/weekly/test", h.TestWeekly)
}
