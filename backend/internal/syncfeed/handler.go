package syncfeed

import (
	"net/http"
	"strconv"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type Handler struct {
	reader ChangeReader
}

func NewHandler(reader ChangeReader) *Handler {
	return &Handler{reader: reader}
}

func (h *Handler) ListChanges(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	after, err := parseNonNegative(c.QueryParam("after"), 0)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid after cursor")
	}
	limit64, err := parseNonNegative(c.QueryParam("limit"), 100)
	if err != nil || limit64 == 0 {
		return web.JSONError(c, http.StatusBadRequest, "invalid limit")
	}
	if limit64 > 500 {
		limit64 = 500
	}

	page, err := h.reader.ListChanges(c.Request().Context(), userID, after, int(limit64))
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "INTERNAL_ERROR")
	}
	return c.JSON(http.StatusOK, page)
}

func parseNonNegative(raw string, fallback int64) (int64, error) {
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || value < 0 {
		return 0, strconv.ErrSyntax
	}
	return value, nil
}
