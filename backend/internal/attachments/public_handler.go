package attachments

import (
	"context"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

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
			return echo.NewHTTPError(http.StatusNotFound)
		}
		return echo.NewHTTPError(http.StatusInternalServerError)
	}
	attachmentID, err := uid.UUIDFromString(c.Param("attachment_id"))
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	delivery, err := h.delivery.Public(c.Request().Context(), noteID, attachmentID)
	if err != nil {
		return echo.NewHTTPError(deliveryErrorStatus(err, true))
	}
	return writeDelivery(c, delivery, "no-store", "no-referrer")
}
