package web

import (
	"errors"
	"net/http"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/pkg/uid"
)

func JSONError(c echo.Context, status int, msg string) error {
	return c.JSON(status, map[string]string{"error": msg})
}

func JSONValidationError(c echo.Context, err error) error {
	var verrs validator.ValidationErrors
	if errors.As(err, &verrs) {
		details := make([]map[string]string, len(verrs))
		for i, ve := range verrs {
			details[i] = map[string]string{
				"field": ve.Field(),
				"tag":   ve.Tag(),
			}
		}
		return c.JSON(http.StatusBadRequest, map[string]any{
			"error":   "validation failed",
			"details": details,
		})
	}
	return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
}

func FormatTime(t pgtype.Timestamptz) string {
	if !t.Valid {
		return ""
	}
	return t.Time.Format(time.RFC3339)
}

func UUIDToString(u pgtype.UUID) string {
	return uid.UUIDToString(u)
}

func OptUUID(s *string) (*pgtype.UUID, error) {
	if s == nil {
		return nil, nil
	}
	parsed, err := uid.UUIDFromString(*s)
	if err != nil {
		return nil, echo.NewHTTPError(http.StatusBadRequest, "invalid uuid")
	}
	return &parsed, nil
}
