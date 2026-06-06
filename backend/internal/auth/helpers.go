package auth

import (
	"errors"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/pkg/uid"
)

// ErrInvalidUserID is returned when the request has no authenticated
// user ID in context or it cannot be parsed.
var ErrInvalidUserID = errors.New("auth: invalid or missing user id")

// UUIDFromString parses a hyphenated UUID and returns a pgtype.UUID,
// returning an invalid value and an error on bad input.
func UUIDFromString(s string) (pgtype.UUID, error) {
	return uid.UUIDFromString(s)
}

// UUIDToString renders a pgtype.UUID as a canonical hyphenated string,
// or "" when the value is null.
func UUIDToString(u pgtype.UUID) string {
	return uid.UUIDToString(u)
}

// ParsedUserID reads the authenticated user ID from the Echo context
// (set by the JWT middleware) and parses it into a pgtype.UUID.
// Returns an invalid value and ErrInvalidUserID when the context has
// no user ID or it cannot be parsed.
func ParsedUserID(c echo.Context) (pgtype.UUID, error) {
	raw, ok := c.Get(userIDContextKey).(string)
	if !ok || raw == "" {
		return pgtype.UUID{}, ErrInvalidUserID
	}
	id, err := uid.UUIDFromString(raw)
	if err != nil {
		return pgtype.UUID{}, ErrInvalidUserID
	}
	return id, nil
}
