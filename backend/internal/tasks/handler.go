package tasks

import (
	"errors"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
	"github.com/labstack/echo/v4"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }
func (h *Handler) RegisterRoutes(g *echo.Group) {
	g.GET("/tasks/bootstrap", h.Bootstrap)
	g.GET("/tasks/:id", h.Get)
	g.POST("/tasks/:id/mutations", h.Mutate)
}
func (h *Handler) Bootstrap(c echo.Context) error {
	u, e := web.UserID(c)
	if e != nil {
		return e
	}
	r, e := h.svc.Bootstrap(c.Request().Context(), u)
	if e != nil {
		c.Logger().Error(e)
		return web.JSONError(c, 500, "failed to bootstrap tasks")
	}
	return c.JSON(200, r)
}
func (h *Handler) Get(c echo.Context) error {
	u, e := web.UserID(c)
	if e != nil {
		return e
	}
	id, e := uid.UUIDFromString(c.Param("id"))
	if e != nil {
		return web.JSONError(c, 400, "invalid id format")
	}
	r, e := h.svc.Get(c.Request().Context(), id, u)
	if errors.Is(e, ErrTaskNotFound) {
		return web.JSONError(c, 404, "task not found")
	}
	if e != nil {
		c.Logger().Error(e)
		return web.JSONError(c, 500, "failed to get task")
	}
	return c.JSON(200, r)
}
func (h *Handler) Mutate(c echo.Context) error {
	u, e := web.UserID(c)
	if e != nil {
		return e
	}
	id, e := uid.UUIDFromString(c.Param("id"))
	if e != nil {
		return web.JSONError(c, 400, "invalid id format")
	}
	var m Mutation
	if e = c.Bind(&m); e != nil {
		return web.JSONError(c, 400, "invalid request body")
	}
	r, e := h.svc.ApplyMutation(c.Request().Context(), u, id, m)
	switch {
	case e == nil:
		return c.JSON(200, r)
	case errors.Is(e, ErrScheduleChanged):
		return web.JSONError(c, 409, "SCHEDULE_CHANGED")
	case errors.Is(e, ErrTaskDeleted):
		return web.JSONError(c, 410, "TASK_DELETED")
	case errors.Is(e, ErrTaskNotFound):
		return web.JSONError(c, 404, "task not found")
	case errors.Is(e, ErrTaskExists):
		return web.JSONError(c, 409, "task already exists")
	case errors.Is(e, ErrHashMismatch) || errors.Is(e, ErrInvalidMutation) || errors.Is(e, ErrNoopMutation):
		return web.JSONError(c, 400, e.Error())
	default:
		c.Logger().Error(e)
		return web.JSONError(c, 500, "failed to apply task mutation")
	}
}
