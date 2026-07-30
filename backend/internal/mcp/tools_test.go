package mcpapp

import (
	"encoding/json"
	"errors"
	"sort"
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
		{"listNotesSchema", listNotesSchema},
		{"idParamSchema", idParamSchema},
		{"noteRevisionSchema", noteRevisionSchema},
		{"noteContentSchema", noteContentSchema},
		{"updateNoteSchema", updateNoteSchema},
		{"taskTitleSchema", taskTitleSchema},
		{"updateTaskSchema", updateTaskSchema},
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

func TestSchemas_noteRevisionRequiresNoteID(t *testing.T) {
	required, ok := noteRevisionSchema["required"].([]any)
	require.True(t, ok)
	assert.Equal(t, []any{"note_id"}, required)
}

func TestGetOptionalTime(t *testing.T) {
	parsed, err := getOptionalTime(map[string]any{"cursor_updated_at": "2026-07-30T12:00:00Z"}, "cursor_updated_at")
	require.NoError(t, err)
	require.NotNil(t, parsed)
	assert.Equal(t, 2026, parsed.Year())
}

func TestGetOptionalTime_rejectsInvalidValue(t *testing.T) {
	_, err := getOptionalTime(map[string]any{"cursor_updated_at": "not-a-time"}, "cursor_updated_at")
	require.Error(t, err)
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

func TestRegisterTools(t *testing.T) {
	server := mcp.NewServer(&mcp.Implementation{Name: "Test"}, nil)
	require.NotPanics(t, func() {
		RegisterTools(server, nil, nil, nil, nil)
	})
}

func TestCurrentToolNames_areRetainedProductContract(t *testing.T) {
	expected := []string{
		"complete_task",
		"create_block",
		"create_note",
		"create_task",
		"delete_block",
		"delete_note",
		"delete_task",
		"get_note",
		"get_note_document",
		"list_note_operations",
		"list_notes",
		"list_tasks",
		"move_block",
		"reopen_task",
		"set_block_metadata",
		"set_block_type",
		"update_block_text",
		"update_note",
		"update_task",
	}

	actual := append([]string(nil), CurrentToolNames...)
	sort.Strings(actual)
	assert.Equal(t, expected, actual)
}

func TestRemovedToolNames_areNotPartOfContract(t *testing.T) {
	for _, removed := range removedToolNames {
		assert.NotContains(t, CurrentToolNames, removed)
	}
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
