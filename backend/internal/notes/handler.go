package notes

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

type CreateNoteRequest struct {
	Title     *string `json:"title"`
	Content   string  `json:"content" validate:"required"`
	ContextID *string `json:"context_id"`
	Favorite  bool    `json:"favorite"`
	Archived  bool    `json:"archived"`
}

type UpdateNoteRequest struct {
	Title     *string `json:"title"`
	Content   *string `json:"content"`
	ContextID *string `json:"context_id"`
	Favorite  *bool   `json:"favorite"`
	Archived  *bool   `json:"archived"`
}

type AppendToInboxRequest struct {
	Content string `json:"content" validate:"required"`
}

type NoteResponse struct {
	ID        string  `json:"id"`
	ContextID *string `json:"context_id,omitempty"`
	Title     *string `json:"title,omitempty"`
	Content   string  `json:"content"`
	Excerpt   *string `json:"excerpt,omitempty"`
	IsInbox   bool    `json:"is_inbox"`
	Favorite  bool    `json:"favorite"`
	Archived  bool    `json:"archived"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
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

	var req CreateNoteRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	var ctxID *pgtype.UUID
	if req.ContextID != nil {
		parsed, err := auth.UUIDFromString(*req.ContextID)
		if err == nil {
			ctxID = &parsed
		}
	}

	note, err := h.svc.CreateNote(c.Request().Context(), userID, req.Title, req.Content, ctxID, req.Favorite, req.Archived)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create note"})
	}

	return c.JSON(http.StatusCreated, mapToNoteResponse(note))
}

func (h *Handler) List(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var ctxID *pgtype.UUID
	if ctxStr := c.QueryParam("context_id"); ctxStr != "" {
		parsed, err := auth.UUIDFromString(ctxStr)
		if err == nil {
			ctxID = &parsed
		}
	}

	var fav *bool
	if favStr := c.QueryParam("favorite"); favStr == "true" {
		t := true
		fav = &t
	} else if favStr == "false" {
		f := false
		fav = &f
	}

	limit := int32(50)

	var cursorUpdatedAt *time.Time
	var cursorID *pgtype.UUID

	// Note: Parse limits and cursors if provided in query param in a real production app.

	notes, err := h.svc.GetNotes(c.Request().Context(), userID, ctxID, fav, limit, cursorUpdatedAt, cursorID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get notes"})
	}

	res := make([]NoteResponse, 0, len(notes))
	for _, n := range notes {
		res = append(res, mapToNoteResponse(n))
	}

	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	note, err := h.svc.GetNoteByID(c.Request().Context(), id, userID)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "note not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get note"})
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
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

	var req UpdateNoteRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	var ctxID *pgtype.UUID
	if req.ContextID != nil {
		parsed, err := auth.UUIDFromString(*req.ContextID)
		if err == nil {
			ctxID = &parsed
		}
	}

	note, err := h.svc.UpdateNote(c.Request().Context(), userID, id, req.Title, req.Content, ctxID, req.Favorite, req.Archived)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "note not found"})
		}
		if errors.Is(err, ErrInboxRule) {
			return c.JSON(http.StatusForbidden, map[string]string{"error": "cannot modify inbox note properties"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update note"})
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
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

	err = h.svc.DeleteNote(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "note not found"})
		}
		if errors.Is(err, ErrInboxRule) {
			return c.JSON(http.StatusForbidden, map[string]string{"error": "cannot delete inbox note"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to delete note"})
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) GetInbox(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	note, err := h.svc.GetInboxNote(c.Request().Context(), userID)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "inbox note not found"})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get inbox note"})
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
}

func (h *Handler) AppendToInbox(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var req AppendToInboxRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	note, err := h.svc.AppendToInbox(c.Request().Context(), userID, req.Content)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to append to inbox note"})
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
}

func mapToNoteResponse(n sqlcgen.Note) NoteResponse {
	var ctxID *string
	if n.ContextID.Valid {
		id := auth.UUIDToString(n.ContextID)
		ctxID = &id
	}
	var title *string
	if n.Title.Valid {
		t := n.Title.String
		title = &t
	}
	var excerpt *string
	if n.Excerpt.Valid {
		e := n.Excerpt.String
		excerpt = &e
	}
	return NoteResponse{
		ID:        auth.UUIDToString(n.ID),
		ContextID: ctxID,
		Title:     title,
		Content:   n.Content,
		Excerpt:   excerpt,
		IsInbox:   n.IsInbox,
		Favorite:  n.Favorite,
		Archived:  n.Archived,
		CreatedAt: n.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: n.UpdatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	}
}
