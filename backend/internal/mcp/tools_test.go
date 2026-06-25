package mcpapp

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSchemas_haveCorrectType(t *testing.T) {
	schemas := []struct {
		name string
		s    map[string]any
	}{
		{"noParamSchema", noParamSchema},
		{"idParamSchema", idParamSchema},
		{"noteContentSchema", noteContentSchema},
		{"updateNoteSchema", updateNoteSchema},
		{"taskTitleSchema", taskTitleSchema},
		{"updateTaskSchema", updateTaskSchema},
		{"contentSchema", contentSchema},
		{"createTagSchema", createTagSchema},
		{"noteTagSchema", noteTagSchema},
		{"updateSoulSchema", updateSoulSchema},
	}
	for _, tt := range schemas {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, "object", tt.s["type"])
		})
	}
}

func TestSchemas_noParamIsEmpty(t *testing.T) {
	assert.Empty(t, noParamSchema["properties"])
	assert.Nil(t, noParamSchema["required"])
}

func TestSchemas_idParam(t *testing.T) {
	props, ok := idParamSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.Contains(t, props, "id")

	required, ok := idParamSchema["required"].([]any)
	require.True(t, ok)
	assert.Equal(t, []any{"id"}, required)
}

func TestSchemas_updateNote(t *testing.T) {
	props, ok := updateNoteSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.Contains(t, props, "id")
	assert.Contains(t, props, "content")

	required, ok := updateNoteSchema["required"].([]any)
	require.True(t, ok)
	assert.ElementsMatch(t, []any{"id", "content"}, required)
}

func TestSchemas_noteTag(t *testing.T) {
	props, ok := noteTagSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.Contains(t, props, "note_id")
	assert.Contains(t, props, "tag_id")

	required, ok := noteTagSchema["required"].([]any)
	require.True(t, ok)
	assert.ElementsMatch(t, []any{"note_id", "tag_id"}, required)
}

func TestRegisterTools(t *testing.T) {
	server := mcp.NewServer(&mcp.Implementation{Name: "Test"}, nil)
	require.NotPanics(t, func() {
		RegisterTools(server, nil, nil, nil, nil, nil)
	})
}

func TestParseArgs(t *testing.T) {
	req := &mcp.CallToolRequest{
		Params: &mcp.CallToolParamsRaw{
			Arguments: json.RawMessage(`{"id":"abc","content":"hello"}`),
		},
	}
	args := parseArgs(req)
	assert.Equal(t, "abc", args["id"])
	assert.Equal(t, "hello", args["content"])
}

func TestParseArgs_invalidJSON(t *testing.T) {
	req := &mcp.CallToolRequest{
		Params: &mcp.CallToolParamsRaw{
			Arguments: json.RawMessage(`not json`),
		},
	}
	args := parseArgs(req)
	assert.Empty(t, args)
}

func TestGetStr_existingKey(t *testing.T) {
	args := map[string]any{"key": "value", "num": 42}
	assert.Equal(t, "value", getStr(args, "key"))
}

func TestGetStr_missingKey(t *testing.T) {
	args := map[string]any{"key": "value"}
	assert.Equal(t, "", getStr(args, "nonexistent"))
}

func TestGetStr_nonStringValue(t *testing.T) {
	args := map[string]any{"num": 42}
	assert.Equal(t, "", getStr(args, "num"))
}

func TestAsText(t *testing.T) {
	result := asText(map[string]string{"msg": "ok"})
	require.Len(t, result, 1)
	tc, ok := result[0].(*mcp.TextContent)
	require.True(t, ok)
	assert.JSONEq(t, `{"msg":"ok"}`, tc.Text)
}

func TestAsError(t *testing.T) {
	err := errors.New("something went wrong")
	res, rerr := asError(err)
	require.Nil(t, rerr)
	require.NotNil(t, res)
	assert.True(t, res.IsError)
	require.Len(t, res.Content, 1)
	tc, ok := res.Content[0].(*mcp.TextContent)
	require.True(t, ok)
	assert.Equal(t, "something went wrong", tc.Text)
}
