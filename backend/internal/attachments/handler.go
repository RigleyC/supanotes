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
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	c.Request().Body = http.MaxBytesReader(c.Response(), c.Request().Body, maxUploadBytes+1024*1024)
	if err := c.Request().ParseMultipartForm(32 << 20); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return web.JSONError(c, http.StatusRequestEntityTooLarge, "O arquivo excede o limite de 200 MB")
		}
		return web.JSONError(c, http.StatusBadRequest, "invalid multipart form")
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

	attachment, err := h.svc.Upload(c.Request().Context(), noteID, userID, file.Filename, src, file.Size)
	if err != nil {
		metrics := h.svc.Metrics()
		if errors.Is(err, ErrFileTooLarge) || errors.Is(err, ErrInvalidFileSize) {
			c.Logger().Warnf(
				"attachment upload rejected note=%s errorClass=%T size=%d rejectedUploads=%d",
				uid.UUIDToString(noteID),
				err,
				file.Size,
				metrics.RejectedUploads,
			)
			return web.JSONError(c, http.StatusRequestEntityTooLarge, "O arquivo excede o limite de 200 MB")
		}
		if errors.Is(err, ErrNoPermission) {
			c.Logger().Warnf(
				"attachment upload rejected note=%s errorClass=%T rejectedUploads=%d",
				uid.UUIDToString(noteID),
				err,
				metrics.RejectedUploads,
			)
			return web.JSONError(c, http.StatusForbidden, "sem permissão para anexar arquivos nesta nota")
		}
		if errors.Is(err, ErrNoteNotFound) {
			c.Logger().Warnf(
				"attachment upload rejected note=%s errorClass=%T rejectedUploads=%d",
				uid.UUIDToString(noteID),
				err,
				metrics.RejectedUploads,
			)
			return web.JSONError(c, http.StatusNotFound, "nota não encontrada")
		}
		c.Logger().Errorf(
			"attachment upload failed note=%s errorClass=%T rejectedUploads=%d",
			uid.UUIDToString(noteID),
			err,
			metrics.RejectedUploads,
		)
		return web.JSONError(c, http.StatusInternalServerError, "upload failed")
	}

	return c.JSON(http.StatusCreated, AttachmentResponse{
		ID:        uid.UUIDToString(attachment.ID),
		NoteID:    uid.UUIDToString(attachment.NoteID),
		Filename:  attachment.Filename,
		URL:       "/api/v1/attachments/" + uid.UUIDToString(attachment.ID) + "/content",
		MimeType:  attachment.MimeType,
		SizeBytes: attachment.SizeBytes,
		CreatedAt: attachment.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	})
}
