package attachments

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/require"
)

func TestParsePermissionResponseRejectsNilAndUnknownValues(t *testing.T) {
	t.Parallel()

	for _, value := range []any{nil, 42, pgtype.Text{Valid: false}} {
		value := value
		t.Run("invalid", func(t *testing.T) {
			t.Parallel()

			_, err := parsePermissionResponse(value)

			require.ErrorIs(t, err, ErrInvalidPermissionResponse)
		})
	}
}

func TestParsePermissionResponseAcceptsDriverRepresentations(t *testing.T) {
	t.Parallel()

	for _, value := range []any{"edit", []byte("view"), pgtype.Text{String: "owner", Valid: true}} {
		value := value
		t.Run("valid", func(t *testing.T) {
			t.Parallel()

			permission, err := parsePermissionResponse(value)

			require.NoError(t, err)
			require.NotEmpty(t, permission)
		})
	}
}
