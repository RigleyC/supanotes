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
	note, err := h.svc.ResolvePublic(c.Request().Context(), c.Param("token"))
	if err != nil {
		return c.NoContent(http.StatusNotFound)
	}
	return c.JSON(http.StatusOK, AccessResponse{NoteID: note.ID.String()})
}
