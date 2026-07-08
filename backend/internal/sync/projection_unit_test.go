package sync

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseUUIDStr_Valid(t *testing.T) {
	id, err := parseUUIDStr("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	assert.True(t, id.Valid)
}

func TestParseUUIDStr_Invalid(t *testing.T) {
	_, err := parseUUIDStr("not-a-uuid")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "uuid")
}

func TestUUIDToStr_Valid(t *testing.T) {
	id, _ := parseUUIDStr("123e4567-e89b-12d3-a456-426614174000")
	s := uuidToStr(id)
	assert.Equal(t, "123e4567-e89b-12d3-a456-426614174000", s)
}

func TestMsToTimestamptz_Zero(t *testing.T) {
	ts := msToTimestamptz(0)
	assert.False(t, ts.Valid)
}

func TestMsToTimestamptz_NonZero(t *testing.T) {
	ts := msToTimestamptz(1700000000000)
	assert.True(t, ts.Valid)
}

func TestTimestamptzToMS_RoundTrip(t *testing.T) {
	ts := msToTimestamptz(1700000000000)
	ms := timestamptzToMS(ts)
	assert.Equal(t, float64(1700000000000), ms)
}

func TestValidateNoteID_Valid(t *testing.T) {
	err := validateNoteID("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
}

func TestValidateNoteID_Invalid(t *testing.T) {
	err := validateNoteID("bad")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "parse note id")
}

func TestValidateNoteID_Empty(t *testing.T) {
	err := validateNoteID("")
	require.Error(t, err)
}
