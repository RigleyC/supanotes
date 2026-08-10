package sharelinks

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

type activateRequest struct {
	Replace bool `json:"replace"`
}

type PublicDocumentResponse struct {
	Title    string          `json:"title"`
	Document json.RawMessage `json:"document"`
}

func (h *Handler) Status(c echo.Context) error {
	userID, noteID, err := h.ids(c)
	if err != nil {
		return err
	}
	result, err := h.svc.Status(c.Request().Context(), userID, noteID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(http.StatusOK, result)
}

func (h *Handler) Activate(c echo.Context) error {
	userID, noteID, err := h.ids(c)
	if err != nil {
		return err
	}
	var req activateRequest
	if c.Request().ContentLength != 0 {
		if err := c.Bind(&req); err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid request body")
		}
	}
	result, err := h.svc.Activate(c.Request().Context(), userID, noteID, req.Replace)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(http.StatusOK, result)
}

func (h *Handler) Disable(c echo.Context) error {
	userID, noteID, err := h.ids(c)
	if err != nil {
		return err
	}
	if err := h.svc.Disable(c.Request().Context(), userID, noteID); err != nil {
		return h.mapError(c, err)
	}
	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) Public(c echo.Context) error {
	token := c.Param("token")
	snapshot, err := h.svc.PublicSnapshot(c.Request().Context(), token, RenderOptions{
		AttachmentBaseURL: "/s/" + token + "/attachments",
	})
	if err != nil {
		return h.mapPublicError(c, err)
	}

	response := c.Response()
	response.Header().Set("Cache-Control", "no-store")
	response.Header().Set("Referrer-Policy", "no-referrer")
	response.Header().Set("X-Robots-Tag", "noindex, nofollow, noarchive")
	response.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; media-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
	response.Header().Set("Content-Type", "text/html; charset=utf-8")
	return c.Blob(http.StatusOK, "text/html; charset=utf-8", []byte(publicHTML(snapshot.Page)))
}

func (h *Handler) PublicDocument(c echo.Context) error {
	snapshot, err := h.svc.PublicSnapshot(c.Request().Context(), c.Param("token"), RenderOptions{})
	if err != nil {
		return h.mapPublicError(c, err)
	}
	c.Response().Header().Set(echo.HeaderCacheControl, "no-store")
	return c.JSON(http.StatusOK, PublicDocumentResponse{
		Title: snapshot.Page.Title, Document: json.RawMessage(snapshot.Note.Document),
	})
}

func publicHTML(page RenderedPage) string {
	title := htmlEscape(page.Title)
	return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow,noarchive"><meta property="og:title" content="` + title + `"><title>` + title + `</title><style>` + publicCSS + `</style></head><body><main>` + page.HTML + `</main></body></html>`
}

func htmlEscape(value string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&#34;", "'", "&#39;").Replace(value)
}

const publicCSS = `:root{color-scheme:light dark}body{margin:0;font:16px/1.6 system-ui,sans-serif;background:#f7f7f8;color:#1c1c1e}main{box-sizing:border-box;max-width:760px;margin:0 auto;padding:48px 24px 72px;background:#fff;min-height:100vh}h1,h2,h3{line-height:1.2}blockquote{border-left:3px solid #8e8e93;margin-left:0;padding-left:16px;color:#636366}.task{display:flex;gap:8px;align-items:flex-start}.task input{margin-top:.45em}a{color:#007aff}@media(prefers-color-scheme:dark){body{background:#1c1c1e;color:#f2f2f7}main{background:#1c1c1e}}`

func (h *Handler) ids(c echo.Context) (uuid.UUID, uuid.UUID, error) {
	userID, err := web.UserID(c)
	if err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	noteID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return uuid.Nil, uuid.Nil, web.JSONError(c, http.StatusBadRequest, "invalid note id")
	}
	return fromPGUUID(userID), noteID, nil
}

func (h *Handler) mapError(c echo.Context, err error) error {
	switch {
	case errors.Is(err, ErrNotOwner):
		return web.JSONError(c, http.StatusForbidden, "only the note owner can manage the share link")
	case errors.Is(err, pgx.ErrNoRows):
		return web.JSONError(c, http.StatusNotFound, "note not found")
	default:
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to manage share link")
	}
}

func (h *Handler) mapPublicError(c echo.Context, err error) error {
	if errors.Is(err, ErrLinkNotFound) {
		return c.NoContent(http.StatusNotFound)
	}
	c.Logger().Error(err)
	return c.NoContent(http.StatusInternalServerError)
}
