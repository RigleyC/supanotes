package noteoperations

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)



func TestConcurrentDeltasForBlock(t *testing.T) {
	blockID := "b1"
	ops := []Operation{
		{
			Kind:    string(KindTextDelta),
			BlockID: pgtype.Text{String: blockID, Valid: true},
			Payload: []byte(`{"ops":[{"retain":1},{"insert":"a"}]}`),
		},
		{
			Kind:    string(KindTextDelta),
			BlockID: pgtype.Text{String: "b2", Valid: true},
			Payload: []byte(`{"ops":[{"retain":1},{"insert":"b"}]}`),
		},
		{
			Kind:    string(KindDeleteBlock),
			BlockID: pgtype.Text{String: blockID, Valid: true},
			Payload: []byte(`{}`),
		},
	}

	result, err := concurrentDeltasForBlock(ops, blockID)
	require.NoError(t, err)
	assert.Len(t, result, 2)
}


