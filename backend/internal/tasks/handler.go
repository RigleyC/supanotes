package tasks

import (
	"errors"
	"net/http"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
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
	v   *validator.Validate
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var req CreateTaskRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	noteID, err := auth.UUIDFromString(req.NoteID)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid note_id"})
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
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create task"})
	}

	return c.JSON(http.StatusCreated, mapToTaskResponse(task))
}

func (h *Handler) List(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var noteID *pgtype.UUID
	if str := c.QueryParam("note_id"); str != "" {
		if parsed, err := auth.UUIDFromString(str); err == nil {
			noteID = &parsed
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
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get tasks"})
	}

	res := make([]TaskResponse, 0, len(tasks))
	for _, t := range tasks {
		res = append(res, mapToTaskResponse(t))
	}
	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	var req UpdateTaskRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
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
			return c.JSON(http.StatusNotFound, map[string]string{"error": "task not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update task"})
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) Delete(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	err = h.svc.DeleteTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "task not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to delete task"})
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) Complete(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	task, err := h.svc.CompleteTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "task not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to complete task"})
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) Reopen(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	task, err := h.svc.ReopenTask(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrTaskNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "task not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to reopen task"})
	}

	return c.JSON(http.StatusOK, mapToTaskResponse(task))
}

func (h *Handler) Today(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	tasks, err := h.svc.GetTodayTasks(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get today tasks"})
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
		ID:         auth.UUIDToString(t.ID),
		NoteID:     auth.UUIDToString(t.NoteID),
		Title:      t.Title,
		Status:     t.Status,
		DueDate:    due,
		Recurrence: rec,
		Position:   int(t.Position),
		CreatedAt:  t.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt:  t.UpdatedAt.Time.Format(time.RFC3339),
	}
}
