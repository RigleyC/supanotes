package notes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

const (
	DestNewNote      = "new_note"
	DestExistingNote = "existing_note"
	DestKeep         = "keep"
)

type CreateNoteRequest struct {
	Content       string  `json:"content" validate:"required"`
	ContextID     *string `json:"context_id"`
	Favorite      bool    `json:"favorite"`
	Archived      bool    `json:"archived"`
	HideCompleted bool    `json:"hide_completed"`
}

type UpdateNoteRequest struct {
	Content       *string `json:"content"`
	ContextID     *string `json:"context_id"`
	Favorite      *bool   `json:"favorite"`
	Archived      *bool   `json:"archived"`
	HideCompleted *bool   `json:"hide_completed"`
}

type AppendToInboxRequest struct {
	Content string `json:"content" validate:"required"`
}

type NoteResponse struct {
	ID            string  `json:"id"`
	ContextID     *string `json:"context_id,omitempty"`
	Content       string  `json:"content"`
	Excerpt       *string `json:"excerpt,omitempty"`
	IsInbox       bool    `json:"is_inbox"`
	Favorite      bool    `json:"favorite"`
	Archived      bool    `json:"archived"`
	HideCompleted bool    `json:"hide_completed"`
	CreatedAt     string  `json:"created_at"`
	UpdatedAt     string  `json:"updated_at"`
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

	note, err := h.svc.CreateNote(c.Request().Context(), userID, req.Content, ctxID, req.Favorite, req.Archived, req.HideCompleted)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create note")
	}

	return c.JSON(http.StatusCreated, mapToNoteResponse(note))
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
		res = append(res, mapToNoteResponse(n))
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

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
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

	note, err := h.svc.UpdateNote(c.Request().Context(), userID, id, req.Content, ctxID, req.Favorite, req.Archived, req.HideCompleted)
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

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
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

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
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

	return c.JSON(http.StatusOK, mapToNoteResponse(note))
}

type PlanOrganizationResponse struct {
	PlanID string                 `json:"plan_id"`
	Items  []PlanOrganizationItem `json:"items"`
}
type PlanOrganizationItem struct {
	ItemID            string  `json:"item_id"`
	OriginalSnippet   string  `json:"original_snippet"`
	DestinationType   string  `json:"destination_type"`
	DestinationNoteID *string `json:"destination_note_id,omitempty"`
	DestinationTitle  *string `json:"destination_title,omitempty"`
	Accepted          bool    `json:"accepted"`
}

type ApplyOrganizationRequest struct {
	PlanID string                 `json:"plan_id"`
	Items  []PlanOrganizationItem `json:"items" validate:"required"`
}

type ApplyOrganizationResponse struct {
	Status string `json:"status"`
}

type llmPlanItem struct {
	Snippet     string `json:"snippet"`
	Destination string `json:"destination"`
	Title       string `json:"title,omitempty"`
}

func (h *Handler) planWithLLM(ctx context.Context, noteContent string) ([]llmPlanItem, error) {
	systemPrompt := `Você é um organizador de notas. Analise o conteúdo do inbox abaixo e organize cada item.

O inbox contém várias anotações separadas por linhas em branco. Para cada anotação, decida o destino:
- "new_note": virar uma nova nota → forneça um título descritivo curto
- "keep": permanecer no inbox (anotações vagas, lembretes rápidos, ideas não desenvolvidas)

Responda APENAS com um JSON array válido. Exemplo:
[{"snippet": "primeira anotação", "destination": "new_note", "title": "Título Descritivo"},
 {"snippet": "segunda anotação", "destination": "keep"}]`

	resp, err := h.llmClient.Complete(ctx, llm.Request{
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: "Aqui está meu inbox:\n\n" + noteContent},
		},
		MaxTokens:   2000,
		Temperature: 0.3,
	})
	if err != nil {
		return nil, fmt.Errorf("llm planning failed: %w", err)
	}

	content := strings.TrimSpace(resp.Content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var planItems []llmPlanItem
	if err := json.Unmarshal([]byte(content), &planItems); err != nil {
		return nil, fmt.Errorf("failed to parse llm plan: %w", err)
	}
	return planItems, nil
}

func (h *Handler) PlanOrganization(c echo.Context) error {
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

	llmItems, err := h.planWithLLM(c.Request().Context(), note.Content)
	if err != nil {
		c.Logger().Errorf("ai planning failed, falling back to mechanical split: %v", err)
		llmItems = h.fallbackPlan(note.Content)
	}

	items := make([]PlanOrganizationItem, 0, len(llmItems))
	noteIDStr := uid.UUIDToString(note.ID)

	snippetIndex := 0

	for _, li := range llmItems {
		trimmedSnippet := strings.TrimSpace(li.Snippet)
		if trimmedSnippet == "" {
			continue
		}
		itemID := fmt.Sprintf("%s-%d", noteIDStr, snippetIndex)
		snippetIndex++

		displaySnippet := trimmedSnippet
		if len(displaySnippet) > 150 {
			displaySnippet = displaySnippet[:150] + "..."
		}

		item := PlanOrganizationItem{
			ItemID:          itemID,
			OriginalSnippet: displaySnippet,
			DestinationType: li.Destination,
			Accepted:        true,
		}
		if li.Destination == DestNewNote && li.Title != "" {
			item.DestinationTitle = &li.Title
		}
		items = append(items, item)
	}

	planID := uuid.New().String()
	return c.JSON(http.StatusOK, PlanOrganizationResponse{
		PlanID: planID,
		Items:  items,
	})
}

func (h *Handler) fallbackPlan(noteContent string) []llmPlanItem {
	lines := strings.Split(noteContent, "\n\n")
	var items []llmPlanItem
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		items = append(items, llmPlanItem{
			Snippet:     trimmed,
			Destination: DestNewNote,
		})
	}
	if len(items) == 0 {
		trimmed := strings.TrimSpace(noteContent)
		if trimmed != "" {
			items = append(items, llmPlanItem{
				Snippet:     trimmed,
				Destination: DestKeep,
			})
		}
	}
	return items
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

func mapToNoteResponse(n sqlcgen.Note) NoteResponse {
	var ctxID *string
	if n.ContextID.Valid {
		id := uid.UUIDToString(n.ContextID)
		ctxID = &id
	}
	var excerpt *string
	if n.Excerpt.Valid {
		e := n.Excerpt.String
		excerpt = &e
	}
	return NoteResponse{
		ID:            uid.UUIDToString(n.ID),
		ContextID:     ctxID,
		Content:       n.Content,
		Excerpt:       excerpt,
		IsInbox:       n.IsInbox,
		Favorite:      n.Favorite,
		Archived:      n.Archived,
		HideCompleted: n.HideCompleted,
		CreatedAt:     n.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:     n.UpdatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	}
}
