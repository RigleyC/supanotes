package attachments

import (
	"context"
	"errors"
	"mime"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/pkg/uid"
)

// PublicNoteResolver validates a share token and returns its note id.
type PublicNoteResolver func(ctx context.Context, token string) (pgtype.UUID, error)

type PublicHandler struct {
	repo    Repository
	storage StorageService
	resolve PublicNoteResolver
}

func NewPublicHandler(repo Repository, storage StorageService, resolve PublicNoteResolver) *PublicHandler {
	return &PublicHandler{repo: repo, storage: storage, resolve: resolve}
}

func (h *PublicHandler) Download(c echo.Context) error {
	noteID, err := h.resolve(c.Request().Context(), c.Param("token"))
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	attachmentID, err := uid.UUIDFromString(c.Param("attachment_id"))
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	attachment, err := h.repo.GetByID(c.Request().Context(), attachmentID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return echo.NewHTTPError(http.StatusNotFound)
		}
		return echo.NewHTTPError(http.StatusNotFound)
	}
	if attachment.NoteID != noteID {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	key, err := storageKeyFromURL(attachment.Url)
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	body, err := h.storage.Open(c.Request().Context(), key)
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	defer body.Close()
	c.Response().Header().Set(echo.HeaderCacheControl, "no-store")
	c.Response().Header().Set("Referrer-Policy", "no-referrer")
	c.Response().Header().Set("X-Content-Type-Options", "nosniff")
	c.Response().Header().Set("Content-Security-Policy", "sandbox")
	if disposition := mime.FormatMediaType("attachment", map[string]string{"filename": attachment.Filename}); disposition != "" {
		c.Response().Header().Set(echo.HeaderContentDisposition, disposition)
	}
	return c.Stream(http.StatusOK, attachment.MimeType, body)
}
