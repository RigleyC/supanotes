package mapper

import (
	"time"

	"github.com/RigleyC/supanotes/pkg/uid"
	"github.com/jackc/pgx/v5/pgtype"
)

func UUID(u pgtype.UUID) string {
	return uid.UUIDToString(u)
}

func OptUUID(u pgtype.UUID) *string {
	if !u.Valid {
		return nil
	}
	s := uid.UUIDToString(u)
	return &s
}

func Time(t pgtype.Timestamptz) string {
	if !t.Valid {
		return ""
	}
	return t.Time.Format(time.RFC3339)
}

func OptTime(t pgtype.Timestamptz) *string {
	if !t.Valid {
		return nil
	}
	s := t.Time.Format(time.RFC3339)
	return &s
}

func Date(d pgtype.Date) string {
	if !d.Valid {
		return ""
	}
	return d.Time.Format(time.RFC3339)
}
