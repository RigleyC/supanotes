package attachments

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AttachmentResponse struct {
	ID        string `json:"id"`
	NoteID    string `json:"note_id"`
	Filename  string `json:"filename"`
	URL       string `json:"url"`
	MimeType  string `json:"mime_type"`
	SizeBytes int64  `json:"size_bytes"`
	CreatedAt string `json:"created_at"`
}

type Handler struct {
	svc Service
}

func NewHandler(svc Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Upload(c echo.Context) error {
	_, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteIDStr := c.FormValue("note_id")
	noteID, err := uid.UUIDFromString(noteIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	file, err := c.FormFile("file")
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "missing file field")
	}

	src, err := file.Open()
	if err != nil {
		return web.JSONError(c, http.StatusInternalServerError, "cannot open uploaded file")
	}
	defer src.Close()

	attachment, err := h.svc.Upload(c.Request().Context(), noteID, file.Filename, src, file.Size)
	if err != nil {
		if errors.Is(err, ErrFileTooLarge) {
			return web.JSONError(c, http.StatusRequestEntityTooLarge, "O arquivo excede o limite de 200 MB")
		}
		c.Logger().Errorf("attachment upload failed: %v", err)
		return web.JSONError(c, http.StatusInternalServerError, "upload failed")
	}

	return c.JSON(http.StatusCreated, AttachmentResponse{
		ID:        uid.UUIDToString(attachment.ID),
		NoteID:    uid.UUIDToString(attachment.NoteID),
		Filename:  attachment.Filename,
		URL:       attachment.Url,
		MimeType:  attachment.MimeType,
		SizeBytes: attachment.SizeBytes,
		CreatedAt: attachment.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	})
}
