package mcpapp

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type captureDocumentCommands struct {
	request noteoperations.SyncRequest
}

func (c *captureDocumentCommands) SyncOperations(
	_ context.Context,
	_ pgtype.UUID,
	_ pgtype.UUID,
	request noteoperations.SyncRequest,
) (noteoperations.SyncResponse, error) {
	c.request = request
	return noteoperations.SyncResponse{FinalRevision: int64(len(request.Operations))}, nil
}

type auditTestSecurityStore struct {
	auditCalls int
	failAt     int
}

type noOpConfirmationLease struct{}

func (noOpConfirmationLease) Commit(context.Context) error  { return nil }
func (noOpConfirmationLease) Release(context.Context) error { return nil }

func (s *auditTestSecurityStore) Audit(context.Context, AuditEvent) error {
	s.auditCalls++
	if s.auditCalls == s.failAt {
		return errors.New("audit unavailable")
	}
	return nil
}

func (s *auditTestSecurityStore) CreateConfirmation(context.Context, pgtype.UUID, string, string, json.RawMessage) (Confirmation, error) {
	return Confirmation{}, nil
}

func (s *auditTestSecurityStore) ReserveConfirmation(context.Context, pgtype.UUID, pgtype.UUID, string, string, json.RawMessage) (ConfirmationLease, error) {
	return noOpConfirmationLease{}, nil
}

func callTestTool(t *testing.T, security SecurityStore, handler mcp.ToolHandler) *mcp.CallToolResult {
	t.Helper()
	server := mcp.NewServer(&mcp.Implementation{Name: "Test"}, nil)
	addTool(server, security, &mcp.Tool{Name: "test_tool", InputSchema: noParamSchema}, handler)
	clientTransport, serverTransport := mcp.NewInMemoryTransports()
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	ctx := context.WithValue(context.Background(), userContextKey, userID)
	ctx = context.WithValue(ctx, mcpScopesKey, []string{"read", "write"})
	serverSession, err := server.Connect(ctx, serverTransport, nil)
	require.NoError(t, err)
	defer serverSession.Close()
	client := mcp.NewClient(&mcp.Implementation{Name: "audit-test-agent", Version: "1"}, nil)
	clientSession, err := client.Connect(context.Background(), clientTransport, nil)
	require.NoError(t, err)
	defer clientSession.Close()
	result, err := clientSession.CallTool(context.Background(), &mcp.CallToolParams{Name: "test_tool", Arguments: map[string]any{}})
	require.NoError(t, err)
	return result
}

func TestAddTool_auditFailureBeforeExecutionBlocksHandler(t *testing.T) {
	security := &auditTestSecurityStore{failAt: 1}
	executions := 0

	result := callTestTool(t, security, func(context.Context, *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		executions++
		return asTextResult("ok")
	})

	assert.True(t, result.IsError)
	assert.Zero(t, executions)
}

func TestAddTool_finalAuditFailureDoesNotTurnCommittedResultIntoRetryableError(t *testing.T) {
	security := &auditTestSecurityStore{failAt: 2}
	executions := 0

	result := callTestTool(t, security, func(context.Context, *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		executions++
		return asTextResult("ok")
	})

	assert.False(t, result.IsError)
	assert.Equal(t, 1, executions)
	assert.Contains(t, result.Content[len(result.Content)-1].(*mcp.TextContent).Text, "MCP audit warning")
}

func TestSchemas_haveCorrectType(t *testing.T) {
	schemas := []struct {
		name string
		s    map[string]any
	}{
		{"noParamSchema", noParamSchema},
		{"listNotesSchema", listNotesSchema},
		{"idParamSchema", idParamSchema},
		{"destructiveIDSchema", destructiveIDSchema},
		{"attachmentUploadSchema", attachmentUploadSchema},
		{"attachmentDeleteSchema", attachmentDeleteSchema},
		{"blockMutationSchema", blockMutationSchema},
		{"destructiveBlockMutationSchema", destructiveBlockMutationSchema},
		{"noteRevisionSchema", noteRevisionSchema},
		{"noteContentSchema", noteContentSchema},
		{"updateNoteSchema", updateNoteSchema},
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
	assert.NotContains(t, props, "confirmation_id")

	required, ok := idParamSchema["required"].([]any)
	require.True(t, ok)
	assert.Equal(t, []any{"id"}, required)
}

func TestSchemas_destructiveInputsExposeOnlyTheirOwnConfirmationArguments(t *testing.T) {
	attachmentProps, ok := attachmentDeleteSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.Contains(t, attachmentProps, "attachment_id")
	assert.Contains(t, attachmentProps, "confirmation_id")
	assert.NotContains(t, attachmentProps, "note_id")

	blockProps, ok := blockMutationSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.NotContains(t, blockProps, "confirmation_id")
	destructiveBlockProps, ok := destructiveBlockMutationSchema["properties"].(map[string]any)
	require.True(t, ok)
	assert.Contains(t, destructiveBlockProps, "confirmation_id")
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
		RegisterTools(server, ServerDependencies{Security: &inMemorySecurityStore{}})
	})
}

func TestCurrentToolNames_areRetainedProductContract(t *testing.T) {
	expected := []string{
		"complete_task_occurrence",
		"create_block",
		"create_note",
		"create_task_block",
		"delete_attachment",
		"delete_block",
		"delete_note",
		"get_note",
		"get_note_document",
		"get_user_settings",
		"list_note_attachments",
		"list_note_operations",
		"list_note_shares",
		"list_notes",
		"list_tasks",
		"move_block",
		"remove_note_share",
		"reopen_task_occurrence",
		"set_block_metadata",
		"set_block_type",
		"share_note",
		"update_block_text",
		"update_note",
		"update_task_metadata",
		"update_user_settings",
		"upload_attachment",
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
	args, err := parseArgs(req)
	require.NoError(t, err)
	assert.Equal(t, "abc", args["id"])
	assert.Equal(t, "hello", args["content"])
}

func TestParseArgs_invalidJSON(t *testing.T) {
	req := &mcp.CallToolRequest{
		Params: &mcp.CallToolParamsRaw{
			Arguments: json.RawMessage(`not json`),
		},
	}
	args, err := parseArgs(req)
	assert.Nil(t, args)
	assert.Error(t, err)
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

func TestAsTextResult(t *testing.T) {
	result, err := asTextResult(map[string]string{"msg": "ok"})
	require.NoError(t, err)
	require.Len(t, result.Content, 1)
	tc, ok := result.Content[0].(*mcp.TextContent)
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

func TestSyncNoteContentUsesCanonicalReplaceOperations(t *testing.T) {
	commands := &captureDocumentCommands{}
	noteID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)

	response, err := syncNoteContent(
		context.Background(),
		commands,
		noteID,
		userID,
		7,
		noteoperations.NewEmptyDocument(),
		"texto novo",
	)
	require.NoError(t, err)
	assert.Equal(t, int64(2), response.FinalRevision)
	require.Len(t, commands.request.Operations, 2)
	assert.Equal(t, string(noteoperations.KindDeleteBlock), commands.request.Operations[0].Kind)
	assert.Equal(t, "init", *commands.request.Operations[0].BlockID)
	assert.Equal(t, string(noteoperations.KindCreateBlock), commands.request.Operations[1].Kind)
	assert.Equal(t, int64(7), commands.request.KnownRevision)

	var payload struct {
		ID    string `json:"id"`
		Type  string `json:"type"`
		Delta []struct {
			Insert string `json:"insert"`
		} `json:"delta"`
	}
	require.NoError(t, json.Unmarshal(commands.request.Operations[1].Payload, &payload))
	assert.Equal(t, "init", payload.ID)
	assert.Equal(t, string(noteoperations.BlockParagraph), payload.Type)
	require.Len(t, payload.Delta, 1)
	assert.Equal(t, "texto novo", payload.Delta[0].Insert)
}
