package noteoperations

import (
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTransformDeltas(t *testing.T) {
	clientDelta := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune("A")},
	}
	serverDelta := []delta.Op{
		{Retain: intPtr(3)},
		{Insert: []rune("B")},
	}

	result, err := TransformDeltas(clientDelta, serverDelta)
	require.NoError(t, err)
	assert.NotNil(t, result)
	assert.True(t, len(result) > 0)
}

func TestTransformDeltasConcurrentInsertSamePosition(t *testing.T) {
	clientOps := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune("!")},
	}
	serverOps := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune(" world")},
	}

	client := delta.New(clientOps)
	server := delta.New(serverOps)

	result := server.Transform(*client, true)

	base := delta.New([]delta.Op{{Insert: []rune("hello")}})
	composed := base.Compose(*server).Compose(*result)
	text := deltaText(composed.Ops)

	assert.Equal(t, "hello world!", text)
}

func TestTransformDeltasClientPriority(t *testing.T) {
	clientOps := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune("!")},
	}
	serverOps := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune(" world")},
	}

	client := delta.New(clientOps)
	server := delta.New(serverOps)

	result := server.Transform(*client, false)

	base := delta.New([]delta.Op{{Insert: []rune("hello")}})
	composed := base.Compose(*server).Compose(*result)
	text := deltaText(composed.Ops)

	assert.Equal(t, "hello! world", text)
}

func TestComposeDeltas(t *testing.T) {
	base := []delta.Op{{Insert: []rune("hello")}}
	change := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune(" world")},
	}

	result, err := ComposeDeltas(base, change)
	require.NoError(t, err)

	text := deltaText(result)
	assert.Equal(t, "hello world", text)
}

func TestInvertDelta(t *testing.T) {
	base := []delta.Op{{Insert: []rune("hello")}}
	change := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune(" world")},
	}

	inverted, err := InvertDelta(change, base)
	require.NoError(t, err)
	assert.NotNil(t, inverted)
}

func TestTransformClientDeltasAgainstConcurrent(t *testing.T) {
	client := []delta.Op{
		{Retain: intPtr(5)},
		{Insert: []rune("X")},
	}
	concurrent := []delta.Op{
		{Retain: intPtr(3)},
		{Insert: []rune("Y")},
	}

	result, err := TransformClientDeltasAgainstConcurrent(client, concurrent)
	require.NoError(t, err)
	assert.NotNil(t, result)
}

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


