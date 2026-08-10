package attachments

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type PrivateHandler struct {
	delivery *DeliveryService
}

func NewPrivateHandler(repo Repository, storage StorageService) *PrivateHandler {
	return &PrivateHandler{delivery: NewDeliveryService(repo, storage)}
}

func (h *PrivateHandler) Download(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}
	attachmentID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid attachment id")
	}
	delivery, err := h.delivery.Authenticated(c.Request().Context(), userID, attachmentID)
	if err != nil {
		return web.JSONError(c, deliveryErrorStatus(err, false), deliveryErrorMessage(err))
	}
	return writeDelivery(c, delivery, "private, no-store", "")
}
