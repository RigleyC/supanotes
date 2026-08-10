package attachments

import (
	"errors"
	"mime"
	"net/http"

	"github.com/labstack/echo/v4"
)

func writeDelivery(c echo.Context, delivery AttachmentDelivery, cacheControl string, referrerPolicy string) error {
	defer delivery.Body.Close()
	c.Response().Header().Set(echo.HeaderCacheControl, cacheControl)
	c.Response().Header().Set("X-Content-Type-Options", "nosniff")
	c.Response().Header().Set("Content-Security-Policy", "sandbox")
	if referrerPolicy != "" {
		c.Response().Header().Set("Referrer-Policy", referrerPolicy)
	}
	if disposition := mime.FormatMediaType("attachment", map[string]string{"filename": delivery.Filename}); disposition != "" {
		c.Response().Header().Set(echo.HeaderContentDisposition, disposition)
	}
	return c.Stream(http.StatusOK, delivery.MimeType, delivery.Body)
}

func deliveryErrorStatus(err error, public bool) int {
	if errors.Is(err, ErrAttachmentNotFound) {
		return http.StatusNotFound
	}
	if !public && errors.Is(err, ErrAttachmentForbidden) {
		return http.StatusForbidden
	}
	return http.StatusInternalServerError
}
