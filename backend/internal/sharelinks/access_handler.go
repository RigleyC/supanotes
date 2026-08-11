package sharelinks

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// AccessResponse is the small, non-content response used by the native app to
// validate a Share Link before deciding between the editor and guest reader.
type AccessResponse struct {
	NoteID string `json:"note_id"`
}

func (h *Handler) Access(c echo.Context) error {
	noteID, err := h.svc.ResolvePublicID(c.Request().Context(), c.Param("token"))
	if err != nil {
		return h.mapPublicError(c, err)
	}
	return c.JSON(http.StatusOK, AccessResponse{NoteID: noteID.String()})
}
