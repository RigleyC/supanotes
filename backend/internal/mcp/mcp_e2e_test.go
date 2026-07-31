package mcpapp

import (
	"context"
	"encoding/json"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type inMemorySecurityStore struct {
	mu     sync.Mutex
	audits []AuditEvent
}

type inMemoryConfirmationLease struct{}

func (inMemoryConfirmationLease) Commit(context.Context) error  { return nil }
func (inMemoryConfirmationLease) Release(context.Context) error { return nil }

func (s *inMemorySecurityStore) Audit(_ context.Context, event AuditEvent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.audits = append(s.audits, event)
	return nil
}

func (s *inMemorySecurityStore) CreateConfirmation(_ context.Context, _ pgtype.UUID, _ string, _ string, _ json.RawMessage) (Confirmation, error) {
	return Confirmation{}, nil
}

func (s *inMemorySecurityStore) ReserveConfirmation(context.Context, pgtype.UUID, pgtype.UUID, string, string, json.RawMessage) (ConfirmationLease, error) {
	return inMemoryConfirmationLease{}, nil
}

type inMemoryDocumentService struct {
	mu         sync.Mutex
	commands   []noteoperations.SyncRequest
	operations map[string]noteoperations.SyncResponse
	document   json.RawMessage
}

func (s *inMemoryDocumentService) SyncOperations(_ context.Context, _ pgtype.UUID, _ pgtype.UUID, request noteoperations.SyncRequest) (noteoperations.SyncResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.operations == nil {
		s.operations = map[string]noteoperations.SyncResponse{}
	}
	operationID := request.Operations[0].OperationID
	if existing, ok := s.operations[operationID]; ok {
		return existing, nil
	}
	s.commands = append(s.commands, request)
	response := noteoperations.SyncResponse{
		Accepted:          []noteoperations.AcceptedOperation{{OperationID: operationID, Revision: 1, Kind: request.Operations[0].Kind}},
		FinalRevision:     1,
		CanonicalDocument: s.document,
		ServerTime:        time.Now().UTC(),
	}
	s.operations[operationID] = response
	return response, nil
}

func (s *inMemoryDocumentService) GetDocument(_ context.Context, noteID pgtype.UUID, _ pgtype.UUID) (noteoperations.DocumentResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return noteoperations.DocumentResponse{NoteID: noteID.String(), Revision: 1, Document: s.document, ServerTime: time.Now().UTC()}, nil
}

func (s *inMemoryDocumentService) GetOperationsSince(context.Context, pgtype.UUID, pgtype.UUID, int64) (noteoperations.OperationsListResponse, error) {
	return noteoperations.OperationsListResponse{Document: s.document, Revision: 1}, nil
}

// TestMCPProtocolFlow_inMemoryUsesCanonicalCommandAndReadSeams verifies the
// MCP transport, tool contract, audit lifecycle, and REST/OT command seams.
// Persistence and external attachment storage are covered by their service
// integration tests; this test does not pretend to be a full product E2E test.
func TestMCPProtocolFlow_inMemoryUsesCanonicalCommandAndReadSeams(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	document := json.RawMessage(`{"blocks":[{"id":"block-1","type":"paragraph","text":"hello"}]}`)
	security := &inMemorySecurityStore{}
	documentService := &inMemoryDocumentService{document: document}
	server := mcp.NewServer(&mcp.Implementation{Name: "Test"}, nil)
	RegisterTools(server, ServerDependencies{
		Security:         security,
		DocumentReader:   documentService,
		DocumentCommands: documentService,
	})

	clientTransport, serverTransport := mcp.NewInMemoryTransports()
	ctx := context.WithValue(context.Background(), userContextKey, userID)
	ctx = context.WithValue(ctx, mcpScopesKey, []string{"read", "write"})
	serverSession, err := server.Connect(ctx, serverTransport, nil)
	require.NoError(t, err)
	defer serverSession.Close()

	client := mcp.NewClient(&mcp.Implementation{Name: "e2e-test-agent", Version: "1"}, nil)
	clientSession, err := client.Connect(context.Background(), clientTransport, nil)
	require.NoError(t, err)
	defer clientSession.Close()

	tools, err := clientSession.ListTools(context.Background(), nil)
	require.NoError(t, err)
	require.Len(t, tools.Tools, len(CurrentToolNames))
	actualNames := make([]string, 0, len(tools.Tools))
	for _, tool := range tools.Tools {
		actualNames = append(actualNames, tool.Name)
	}
	sort.Strings(actualNames)
	expectedNames := append([]string(nil), CurrentToolNames...)
	sort.Strings(expectedNames)
	require.Equal(t, expectedNames, actualNames)

	noteID := "123e4567-e89b-12d3-a456-426614174001"
	operationID := "123e4567-e89b-12d3-a456-426614174002"
	result, err := clientSession.CallTool(context.Background(), &mcp.CallToolParams{
		Name: "create_block",
		Arguments: map[string]any{
			"note_id":       noteID,
			"base_revision": 0,
			"operation_id":  operationID,
			"payload":       map[string]any{"type": "paragraph"},
		},
	})
	require.NoError(t, err)
	require.False(t, result.IsError)

	_, err = clientSession.CallTool(context.Background(), &mcp.CallToolParams{
		Name: "create_block",
		Arguments: map[string]any{
			"note_id":       noteID,
			"base_revision": 0,
			"operation_id":  operationID,
			"payload":       map[string]any{"type": "paragraph"},
		},
	})
	require.NoError(t, err)
	documentResult, err := clientSession.CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "get_note_document",
		Arguments: map[string]any{"id": noteID},
	})
	require.NoError(t, err)
	require.False(t, documentResult.IsError)
	require.Len(t, documentService.commands, 1, "retry must remain idempotent at the document seam")
	require.Len(t, security.audits, 6, "each tool call must have start and final audit records")
	require.Equal(t, "e2e-test-agent/1", security.audits[0].Agent)
	require.Equal(t, "started", security.audits[0].Result)
	require.Equal(t, "success", security.audits[1].Result)
	require.Equal(t, document, documentService.document)
}
