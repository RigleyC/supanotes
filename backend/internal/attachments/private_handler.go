package attachments

import (
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type PrivateHandler struct {
	repo    Repository
	storage StorageService
}

func NewPrivateHandler(repo Repository, storage StorageService) *PrivateHandler {
	return &PrivateHandler{repo: repo, storage: storage}
}

func (h *PrivateHandler) Download(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}
	attachmentID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return echo.NewHTTPError(http.StatusBadRequest)
	}
	attachment, err := h.repo.GetByID(c.Request().Context(), attachmentID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return echo.NewHTTPError(http.StatusNotFound)
		}
		return echo.NewHTTPError(http.StatusInternalServerError)
	}
	permission, err := h.repo.CheckNotePermission(c.Request().Context(), attachment.NoteID, userID)
	if err != nil {
		return echo.NewHTTPError(http.StatusInternalServerError)
	}
	if permission == "not_found" {
		return echo.NewHTTPError(http.StatusNotFound)
	}
	if permission != "owner" && permission != "edit" && permission != "view" {
		return echo.NewHTTPError(http.StatusForbidden)
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
	c.Response().Header().Set(echo.HeaderCacheControl, "private, no-store")
	return c.Stream(http.StatusOK, attachment.MimeType, body)
}
