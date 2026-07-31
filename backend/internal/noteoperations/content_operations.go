package noteoperations

import (
	"encoding/json"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/google/uuid"
)

// BuildReplaceContentOperations returns the canonical operation sequence for
// replacing a note with one plain paragraph. The caller still submits the
// sequence through SyncOperations, so revision checks, permission checks,
// persistence, and projections remain owned by the document service.
func BuildReplaceContentOperations(
	doc Document,
	content string,
	baseRevision int64,
) ([]OperationRequest, error) {
	operations := make([]OperationRequest, 0, len(doc.Blocks)+1)
	for _, block := range doc.Blocks {
		blockID := block.ID
		operations = append(operations, OperationRequest{
			OperationID:  uuid.NewString(),
			BaseRevision: baseRevision,
			Kind:         string(KindDeleteBlock),
			BlockID:      &blockID,
			Payload:      json.RawMessage(`{}`),
		})
	}

	createPayload, err := json.Marshal(CreateBlockPayload{
		ID:       InitialBlockID,
		Type:     string(BlockParagraph),
		Delta:    []delta.Op{{Insert: []rune(content)}},
		Metadata: map[string]any{},
	})
	if err != nil {
		return nil, err
	}
	operations = append(operations, OperationRequest{
		OperationID:  uuid.NewString(),
		BaseRevision: baseRevision,
		Kind:         string(KindCreateBlock),
		Payload:      createPayload,
	})

	return operations, nil
}
