package routines

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type UpdateRoutineRequest struct {
	DaysOfWeek *string `json:"days_of_week"` // "mon,wed,fri"
	TimeOfDay  *string `json:"time_of_day"`  // "HH:MM"
	Enabled    *bool   `json:"enabled"`
}

type UpdateRoutineConfigRequest struct {
	TimeOfDay  *string `json:"time_of_day"`  // "HH:MM"
	DaysOfWeek *string `json:"days_of_week"` // "mon,wed,fri"
	Enabled    *bool   `json:"enabled"`
	Timezone   *string `json:"timezone"`
}

type TestRoutineResponse struct {
	Content string `json:"content"`
}

type RoutineResponse struct {
	ID         pgtype.UUID        `json:"id"`
	UserID     pgtype.UUID        `json:"user_id"`
	Type       string             `json:"type"`
	DaysOfWeek string             `json:"days_of_week"`
	TimeOfDay  string             `json:"time_of_day"`
	Enabled    bool               `json:"enabled"`
	CreatedAt  pgtype.Timestamptz `json:"created_at"`
	UpdatedAt  pgtype.Timestamptz `json:"updated_at"`
	Name       string             `json:"name"`
	LastRunAt  pgtype.Timestamptz `json:"last_run_at"`
	BriefType  string             `json:"brief_type"`
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

	resp := make([]RoutineResponse, len(routines))
	for i, r := range routines {
		resp[i] = routineToResponse(r)
	}
	return c.JSON(http.StatusOK, resp)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid routine id")
	}

	var req UpdateRoutineRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	var cronExpr *string
	if req.DaysOfWeek != nil && req.TimeOfDay != nil {
		expr := daysAndTimeToCron(*req.DaysOfWeek, *req.TimeOfDay)
		cronExpr = &expr
	}

	routine, err := h.svc.UpdateRoutine(c.Request().Context(), id, userID, cronExpr, req.Enabled)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update routine")
	}

	return c.JSON(http.StatusOK, routineToResponse(routine))
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

func (h *Handler) UpdateDaily(c echo.Context) error {
	return h.updateByType(c, "daily")
}

func (h *Handler) UpdateWeekly(c echo.Context) error {
	return h.updateByType(c, "weekly")
}

func (h *Handler) updateByType(c echo.Context, routineType string) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req UpdateRoutineConfigRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	routine, err := h.svc.UpdateRoutineByType(c.Request().Context(), userID, routineType, req.TimeOfDay, req.DaysOfWeek, req.Enabled, req.Timezone)
	if err != nil {
		if errors.Is(err, ErrRoutineNotFound) {
			return web.JSONError(c, http.StatusNotFound, "routine not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update routine")
	}

	return c.JSON(http.StatusOK, routineToResponse(*routine))
}

func (h *Handler) GetLatestBrief(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	briefType := c.Param("type")
	if briefType != "daily" && briefType != "weekly" {
		return web.JSONError(c, http.StatusBadRequest, "invalid brief type, must be 'daily' or 'weekly'")
	}

	content, err := h.svc.GetLatestBrief(c.Request().Context(), userID, briefType)
	if err != nil {
		if err == ErrBriefNotFound {
			return web.JSONError(c, http.StatusNotFound, "no brief available yet")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get latest brief")
	}
	return c.JSON(http.StatusOK, TestRoutineResponse{Content: content})
}

var dayAbbrToNum = map[string]string{
	"sun": "0",
	"mon": "1",
	"tue": "2",
	"wed": "3",
	"thu": "4",
	"fri": "5",
	"sat": "6",
}

var dayNumToAbbr = map[string]string{
	"0": "sun",
	"1": "mon",
	"2": "tue",
	"3": "wed",
	"4": "thu",
	"5": "fri",
	"6": "sat",
}

func daysAndTimeToCron(daysOfWeek, timeOfDay string) string {
	parts := strings.Split(timeOfDay, ":")
	minute := "0"
	if len(parts) == 2 {
		minute = parts[1]
	}
	hour := parts[0]

	dayAbbrs := strings.Split(daysOfWeek, ",")
	dayNums := make([]string, len(dayAbbrs))
	for i, abbr := range dayAbbrs {
		dayNums[i] = dayAbbrToNum[strings.ToLower(strings.TrimSpace(abbr))]
	}

	return fmt.Sprintf("%s %s * * %s", minute, hour, strings.Join(dayNums, ","))
}

func cronToDaysAndTime(cronExpr string) (string, string) {
	parts := strings.Split(cronExpr, " ")
	if len(parts) < 5 {
		return "", ""
	}

	hour := parts[1]
	minute := parts[0]
	dayNums := strings.Split(parts[4], ",")

	timeOfDay := fmt.Sprintf("%s:%s", hour, minute)

	dayAbbrs := make([]string, len(dayNums))
	for i, num := range dayNums {
		dayAbbrs[i] = dayNumToAbbr[strings.TrimSpace(num)]
	}

	return strings.Join(dayAbbrs, ","), timeOfDay
}

func routineToResponse(r sqlcgen.Routine) RoutineResponse {
	daysOfWeek, timeOfDay := cronToDaysAndTime(r.CronExpr)
	return RoutineResponse{
		ID:        r.ID,
		UserID:    r.UserID,
		Type:      r.Type,
		DaysOfWeek: daysOfWeek,
		TimeOfDay: timeOfDay,
		Enabled:   r.Enabled,
		CreatedAt: r.CreatedAt,
		UpdatedAt: r.UpdatedAt,
		Name:      r.Name,
		LastRunAt: r.LastRunAt,
		BriefType: r.BriefType,
	}
}

func RegisterRoutes(api *echo.Group, h *Handler) {
	r := api.Group("/routines")
	r.GET("", h.List)
	r.GET("/logs", h.Logs)
	r.GET("/brief/:type", h.GetLatestBrief)
	r.PATCH("/:id", h.Update)
	r.PATCH("/daily", h.UpdateDaily)
	r.PATCH("/weekly", h.UpdateWeekly)
	r.POST("/daily/test", h.TestDaily)
	r.POST("/weekly/test", h.TestWeekly)
}
