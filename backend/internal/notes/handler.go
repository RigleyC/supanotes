package notes

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateNoteRequest struct {
	Content        string `json:"content" validate:"required"`
	CollapseImages bool   `json:"collapse_images"`
}

type UpdateNoteRequest struct {
	Content        *string         `json:"content"`
	CollapseImages *bool           `json:"collapse_images"`
	NoteIcon       json.RawMessage `json:"note_icon"`
}

type NoteResponse struct {
	ID             string  `json:"id"`
	Content        string  `json:"content"`
	Excerpt        *string `json:"excerpt,omitempty"`
	Favorite       bool    `json:"favorite"`
	Archived       bool    `json:"archived"`
	CollapseImages bool    `json:"collapse_images"`
	CreatedAt      string  `json:"created_at"`
	UpdatedAt      string  `json:"updated_at"`
	Permission     string  `json:"permission,omitempty"`
	SharedByEmail  string  `json:"shared_by_email,omitempty"`
	SharedByName   string  `json:"shared_by_name,omitempty"`
	// The field is always present so a remote clear is distinguishable from an
	// older response that did not carry icon metadata.
	NoteIcon json.RawMessage `json:"note_icon"`
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

	var req CreateNoteRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	note, err := h.svc.CreateNote(c.Request().Context(), userID, req.Content, req.CollapseImages)
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
	var fav *bool
	if favStr := c.QueryParam("favorite"); favStr == "true" {
		t := true
		fav = &t
	} else if favStr == "false" {
		f := false
		fav = &f
	}

	limit := int32(50)
	if l := c.QueryParam("limit"); l != "" {
		if parsed, err := parseInt32(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	var cursorUpdatedAt *time.Time
	if cu := c.QueryParam("cursor_updated_at"); cu != "" {
		if parsed, err := time.Parse(time.RFC3339, cu); err == nil {
			cursorUpdatedAt = &parsed
		}
	}
	var cursorID *pgtype.UUID
	if ci := c.QueryParam("cursor_id"); ci != "" {
		cursorID, err = web.OptUUID(&ci)
		if err != nil {
			cursorID = nil
		}
	}

	notes, err := h.svc.GetNotes(c.Request().Context(), userID, fav, limit, cursorUpdatedAt, cursorID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get notes")
	}

	res := make([]NoteResponse, 0, len(notes))
	for _, n := range notes {
		res = append(res, mapToNoteResponse(noteResponseFieldsFromListRow(n)))
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

	return c.JSON(http.StatusOK, mapToNoteResponse(noteResponseFieldsFromGetRow(note)))
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

	noteIcon, err := parseNoteIconPayload(req.NoteIcon)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, err.Error())
	}
	note, err := h.svc.UpdateNote(c.Request().Context(), userID, id, req.Content, req.CollapseImages, noteIcon)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "note not found")
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
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete note")
	}

	return c.NoContent(http.StatusNoContent)
}

func ptr(s string) *string { return &s }

func parseInt32(s string) (int32, error) {
	n, err := strconv.ParseInt(s, 10, 32)
	return int32(n), err
}

type NoteResponseFields struct {
	ID             pgtype.UUID
	Content        string
	Excerpt        pgtype.Text
	Favorite       bool
	Archived       bool
	CollapseImages bool
	CreatedAt      pgtype.Timestamptz
	UpdatedAt      pgtype.Timestamptz
	Permission     string
	SharedByEmail  string
	SharedByName   string
	NoteIcon       []byte
}

func mapToNoteResponse(f NoteResponseFields) NoteResponse {
	var exc *string
	if f.Excerpt.Valid {
		e := f.Excerpt.String
		exc = &e
	}
	return NoteResponse{
		ID:             uid.UUIDToString(f.ID),
		Content:        f.Content,
		Excerpt:        exc,
		Favorite:       f.Favorite,
		Archived:       f.Archived,
		CollapseImages: f.CollapseImages,
		CreatedAt:      f.CreatedAt.Time.Format(time.RFC3339Nano),
		UpdatedAt:      f.UpdatedAt.Time.Format(time.RFC3339Nano),
		Permission:     f.Permission,
		SharedByEmail:  f.SharedByEmail,
		SharedByName:   f.SharedByName,
		NoteIcon:       json.RawMessage(f.NoteIcon),
	}
}

func noteToResponseFields(n sqlcgen.Note) NoteResponseFields {
	return NoteResponseFields{
		ID:             n.ID,
		Content:        n.Content,
		Excerpt:        n.Excerpt,
		CollapseImages: n.CollapseImages,
		CreatedAt:      n.CreatedAt,
		UpdatedAt:      n.UpdatedAt,
		NoteIcon:       n.NoteIcon,
	}
}

func noteResponseFieldsFromGetRow(n sqlcgen.GetNoteByIDRow) NoteResponseFields {
	return NoteResponseFields{
		ID:             n.ID,
		Content:        n.Content,
		Excerpt:        n.Excerpt,
		Favorite:       n.Favorite,
		Archived:       n.Archived,
		CollapseImages: n.CollapseImages,
		CreatedAt:      n.CreatedAt,
		UpdatedAt:      n.UpdatedAt,
		Permission:     n.Permission,
		SharedByEmail:  n.SharedByEmail,
		SharedByName:   n.SharedByName,
		NoteIcon:       n.NoteIcon,
	}
}

func noteResponseFieldsFromListRow(n sqlcgen.GetNotesRow) NoteResponseFields {
	return NoteResponseFields{
		ID:             n.ID,
		Excerpt:        n.Excerpt,
		Favorite:       n.Favorite,
		Archived:       n.Archived,
		CollapseImages: n.CollapseImages,
		CreatedAt:      n.CreatedAt,
		UpdatedAt:      n.UpdatedAt,
		Permission:     n.Permission,
		SharedByEmail:  n.SharedByEmail,
		SharedByName:   n.SharedByName,
		NoteIcon:       n.NoteIcon,
	}
}
