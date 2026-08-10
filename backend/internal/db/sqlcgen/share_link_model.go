package sqlcgen

import "github.com/jackc/pgx/v5/pgtype"

type NoteShareLink struct {
	NoteID    pgtype.UUID        `json:"note_id"`
	TokenID   pgtype.UUID        `json:"token_id"`
	Enabled   bool               `json:"enabled"`
	CreatedAt pgtype.Timestamptz `json:"created_at"`
	UpdatedAt pgtype.Timestamptz `json:"updated_at"`
}
