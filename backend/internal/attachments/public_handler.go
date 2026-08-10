package attachments

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

// PublicNoteResolver validates a share token and returns its note id.
type PublicNoteResolver func(ctx context.Context, token string) (pgtype.UUID, error)

type PublicHandler struct {
	delivery *DeliveryService
	resolve  PublicNoteResolver
}

func NewPublicHandler(repo Repository, storage StorageService, resolve PublicNoteResolver) *PublicHandler {
	return &PublicHandler{delivery: NewDeliveryService(repo, storage), resolve: resolve}
}

func (h *PublicHandler) Download(c echo.Context) error {
	noteID, err := h.resolve(c.Request().Context(), c.Param("token"))
	if err != nil {
		if errors.Is(err, ErrPublicLinkNotFound) {
			return publicDownloadError(c, http.StatusNotFound, "share link not found")
		}
		return publicDownloadError(c, http.StatusInternalServerError, "failed to resolve share link")
	}
	attachmentID, err := uid.UUIDFromString(c.Param("attachment_id"))
	if err != nil {
		return publicDownloadError(c, http.StatusNotFound, "attachment not found")
	}
	delivery, err := h.delivery.Public(c.Request().Context(), noteID, attachmentID)
	if err != nil {
		return publicDownloadError(c, deliveryErrorStatus(err, true), deliveryErrorMessage(err))
	}
	return writeDelivery(c, delivery, "no-store", "no-referrer")
}

func publicDownloadError(c echo.Context, status int, message string) error {
	if strings.HasPrefix(c.Request().URL.Path, "/api/v1/") {
		return web.JSONError(c, status, message)
	}
	return echo.NewHTTPError(status, message)
}
