package tasks

import (
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateTaskRequest struct {
	NoteID     string  `json:"note_id" validate:"required,uuid"`
	Title      string  `json:"title" validate:"required"`
	DueDate    *string `json:"due_date"`
	Recurrence *string `json:"recurrence"`
	Position   int     `json:"position"`
}

type UpdateTaskRequest struct {
	Title      *string `json:"title"`
	Status     *string `json:"status"`
	DueDate    *string `json:"due_date"`
	Recurrence *string `json:"recurrence"`
	Position   *int    `json:"position"`
}

type TaskResponse struct {
	ID         string  `json:"id"`
	NoteID     string  `json:"note_id"`
	Title      string  `json:"title"`
	Status     string  `json:"status"`
	DueDate    *string `json:"due_date,omitempty"`
	Recurrence *string `json:"recurrence,omitempty"`
	Position   int     `json:"position"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
}

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateTaskRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(req.NoteID)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	var dueDate *time.Time
	if req.DueDate != nil {
		t, err := time.Parse(time.RFC3339, *req.DueDate)
		if err == nil {
			dueDate = &t
		}
	}

	task, err := h.svc.CreateTask(c.Request().Context(), userID, noteID, req.Title, dueDate, req.Recurrence, req.Position)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create task")
	}

	return c.JSON(http.StatusCreated, mapToTaskResponse(task))
}

func (h *Handler) List(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var noteID *pgtype.UUID
	if str := c.QueryParam("note_id"); str != "" {
		noteID, err = web.OptUUID(&str)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
		}
	}

	var status *string
	if s := c.QueryParam("status"); s != "" {
		status = &s
	}

	limit := int32(50)

	tasks, err := h.svc.GetTasks(c.Request().Context(), userID, noteID, status, nil, nil, limit, 0)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get tasks")
	}

	res := make([]TaskResponse, 0, len(tasks))
	for _, t := range tasks {
		res = append(res, mapToTaskResponse(t))
	}
	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	var req UpdateTaskRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	var dueDate *time.Time
	if req.DueDate != nil {
		t, err := time.Parse(time.RFC3339, *req.DueDate)
		if err == nil {
			dueDate = &t
		}
	}

	task, err := h.svc.UpdateTask(c.Request().Context(), userID, id, req.Title, req.Status, dueDate, req.Recurrence, req.Position)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return web.JSONError(c, http.StatusNotFound, "task not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update task")
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) Delete(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	err = h.svc.DeleteTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return web.JSONError(c, http.StatusNotFound, "task not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete task")
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) Complete(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	task, err := h.svc.CompleteTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return web.JSONError(c, http.StatusNotFound, "task not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to complete task")
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) Reopen(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	task, err := h.svc.ReopenTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return web.JSONError(c, http.StatusNotFound, "task not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to reopen task")
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) GetByNoteID(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}
	noteID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note id")
	}
	tasks, err := h.svc.GetTasks(c.Request().Context(), userID, &noteID, nil, nil, nil, 100, 0)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get tasks")
	}
	return c.JSON(http.StatusOK, tasks)
}

func (h *Handler) Today(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	tasks, err := h.svc.GetTodayTasks(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get today tasks")
	}

	res := make([]TaskResponse, 0, len(tasks))
	for _, t := range tasks {
		res = append(res, mapToTaskResponse(t))
	}
	return c.JSON(http.StatusOK, res)
}

func mapToTaskResponse(t sqlcgen.Task) TaskResponse {
	var due *string
	if t.DueDate.Valid {
		d := t.DueDate.Time.Format(time.RFC3339)
		due = &d
	}
	var rec *string
	if t.Recurrence.Valid {
		r := t.Recurrence.String
		rec = &r
	}
	return TaskResponse{
		ID:         uid.UUIDToString(t.ID),
		NoteID:     uid.UUIDToString(t.NoteID),
		Title:      t.Title,
		Status:     t.Status,
		DueDate:    due,
		Recurrence: rec,
		Position:   int(t.Position),
		CreatedAt:  t.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt:  t.UpdatedAt.Time.Format(time.RFC3339),
	}
}
