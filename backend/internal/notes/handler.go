package notes

import (
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateNoteRequest struct {
	Content        string  `json:"content" validate:"required"`
	ContextID      *string `json:"context_id"`
	CollapseImages bool    `json:"collapse_images"`
}

type UpdateNoteRequest struct {
	Content        *string `json:"content"`
	ContextID      *string `json:"context_id"`
	CollapseImages *bool   `json:"collapse_images"`
}

type AppendToInboxRequest struct {
	Content string `json:"content" validate:"required"`
}

type NoteResponse struct {
	ID             string  `json:"id"`
	ContextID      *string `json:"context_id,omitempty"`
	Content        string  `json:"content"`
	Excerpt        *string `json:"excerpt,omitempty"`
	IsInbox        bool    `json:"is_inbox"`
	Favorite       bool    `json:"favorite"`
	Archived       bool    `json:"archived"`
	CollapseImages bool    `json:"collapse_images"`
	CreatedAt      string  `json:"created_at"`
	UpdatedAt      string  `json:"updated_at"`
}

type Handler struct {
	svc       *Service
	llmClient llm.Client
}

func NewHandler(svc *Service, llmClient llm.Client) *Handler {
	return &Handler{svc: svc, llmClient: llmClient}
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateNoteRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	var ctxID *pgtype.UUID
	if req.ContextID != nil {
		ctxID, err = web.OptUUID(req.ContextID)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid context_id")
		}
	}

	note, err := h.svc.CreateNote(c.Request().Context(), userID, req.Content, ctxID, req.CollapseImages)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create note")
	}

	return c.JSON(http.StatusCreated, mapToNoteResponse(noteToResponseFields(note)))
}

func (h *Handler) List(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var ctxID *pgtype.UUID
	if ctxStr := c.QueryParam("context_id"); ctxStr != "" {
		ctxID, err = web.OptUUID(&ctxStr)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid context_id")
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
		return web.JSONError(c, http.StatusInternalServerError, "failed to get notes")
	}

	res := make([]NoteResponse, 0, len(notes))
	for _, n := range notes {
		res = append(res, mapToNoteResponse(NoteResponseFields{
			ID: n.ID, ContextID: n.ContextID, Content: n.Content, Excerpt: n.Excerpt,
			IsInbox: n.IsInbox, Favorite: n.Favorite, Archived: n.Archived,
			CollapseImages: n.CollapseImages, CreatedAt: n.CreatedAt, UpdatedAt: n.UpdatedAt,
		}))
	}

	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	note, err := h.svc.GetNoteByID(c.Request().Context(), id, userID)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "note not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get note")
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(NoteResponseFields{
		ID: note.ID, ContextID: note.ContextID, Content: note.Content,
		Excerpt: note.Excerpt, IsInbox: note.IsInbox, Favorite: note.Favorite,
		Archived: note.Archived, CollapseImages: note.CollapseImages,
		CreatedAt: note.CreatedAt, UpdatedAt: note.UpdatedAt,
	}))
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

	var req UpdateNoteRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	var ctxID *pgtype.UUID
	if req.ContextID != nil {
		ctxID, err = web.OptUUID(req.ContextID)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid context_id")
		}
	}

	note, err := h.svc.UpdateNote(c.Request().Context(), userID, id, req.Content, ctxID, req.CollapseImages)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "note not found")
		}
		if errors.Is(err, ErrInboxRule) {
			return web.JSONError(c, http.StatusForbidden, "cannot modify inbox note properties")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update note")
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(noteToResponseFields(note)))
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

	err = h.svc.DeleteNote(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "note not found")
		}
		if errors.Is(err, ErrInboxRule) {
			return web.JSONError(c, http.StatusForbidden, "cannot delete inbox note")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete note")
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) GetInbox(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	note, err := h.svc.GetInboxNote(c.Request().Context(), userID)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "inbox note not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get inbox note")
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(NoteResponseFields{
		ID: note.ID, ContextID: note.ContextID, Content: note.Content,
		Excerpt: note.Excerpt, IsInbox: note.IsInbox, Favorite: note.Favorite,
		Archived: note.Archived, CollapseImages: note.CollapseImages,
		CreatedAt: note.CreatedAt, UpdatedAt: note.UpdatedAt,
	}))
}

func (h *Handler) AppendToInbox(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req AppendToInboxRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	note, err := h.svc.AppendToInbox(c.Request().Context(), userID, req.Content)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to append to inbox note")
	}

	return c.JSON(http.StatusOK, mapToNoteResponse(noteToResponseFields(note)))
}

type PlanOrganizationResponse struct {
	PlanID string                 `json:"plan_id"`
	Items  []PlanOrganizationItem `json:"items"`
}

type ApplyOrganizationRequest struct {
	PlanID string                 `json:"plan_id"`
	Items  []PlanOrganizationItem `json:"items" validate:"required"`
}

type ApplyOrganizationResponse struct {
	Status string `json:"status"`
}

func (h *Handler) PlanOrganization(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	items, err := h.svc.PlanInboxOrganization(c.Request().Context(), userID, h.llmClient)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "inbox note not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to plan inbox organization")
	}

	planID := uuid.New().String()
	return c.JSON(http.StatusOK, PlanOrganizationResponse{
		PlanID: planID,
		Items:  items,
	})
}

func (h *Handler) ApplyOrganization(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req ApplyOrganizationRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	if err := h.svc.ApplyOrganization(c.Request().Context(), userID, req.Items); err != nil {
		return web.JSONError(c, http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusOK, ApplyOrganizationResponse{Status: "applied"})
}

func ptr(s string) *string { return &s }

// NoteResponseFields carries the fields needed to build a NoteResponse.
// It eliminates the long parameter list that was previously passed to a
// mapper function, since the same set of fields comes from several
// sqlc-generated row types (Note, GetNotesRow, GetNoteByIDRow, …).
type NoteResponseFields struct {
	ID             pgtype.UUID
	ContextID      pgtype.UUID
	Content        string
	Excerpt        pgtype.Text
	IsInbox        bool
	Favorite       bool
	Archived       bool
	CollapseImages bool
	CreatedAt      pgtype.Timestamptz
	UpdatedAt      pgtype.Timestamptz
}

func mapToNoteResponse(f NoteResponseFields) NoteResponse {
	var ctxID *string
	if f.ContextID.Valid {
		cid := uid.UUIDToString(f.ContextID)
		ctxID = &cid
	}
	var exc *string
	if f.Excerpt.Valid {
		e := f.Excerpt.String
		exc = &e
	}
	return NoteResponse{
		ID:             uid.UUIDToString(f.ID),
		ContextID:      ctxID,
		Content:        f.Content,
		Excerpt:        exc,
		IsInbox:        f.IsInbox,
		Favorite:       f.Favorite,
		Archived:       f.Archived,
		CollapseImages: f.CollapseImages,
		CreatedAt:      f.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:      f.UpdatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func noteToResponseFields(n sqlcgen.Note) NoteResponseFields {
	return NoteResponseFields{
		ID:             n.ID,
		ContextID:      n.ContextID,
		Content:        n.Content,
		Excerpt:        n.Excerpt,
		IsInbox:        n.IsInbox,
		CollapseImages: n.CollapseImages,
		CreatedAt:      n.CreatedAt,
		UpdatedAt:      n.UpdatedAt,
	}
}
