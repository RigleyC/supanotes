package noteoperations

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

// AppendRichLinkResponse is the canonical document produced by an external
// share. The caller can use the same document/sync path as any other server
// operation.
type AppendRichLinkResponse struct {
	Revision        int64
	Document        json.RawMessage
	AlreadyAccepted bool
}

// AppendRichLink appends one rich_link block after the current last block.
// operationID is the durable share id, so a retry is idempotent for a note.
func (s *Service) AppendRichLink(
	ctx context.Context,
	noteID pgtype.UUID,
	userID pgtype.UUID,
	operationID string,
	metadata map[string]any,
) (AppendRichLinkResponse, error) {
	if _, err := uuid.Parse(operationID); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("invalid operation id: %w", err)
	}
	if s.txRunner == nil {
		return AppendRichLinkResponse{}, errors.New("append rich link requires transaction runner")
	}

	var response AppendRichLinkResponse
	err := s.txRunner.InTx(ctx, s.repo, func(txRepo Repository) error {
		var err error
		response, err = appendRichLinkInRepository(
			ctx,
			txRepo,
			noteID,
			userID,
			operationID,
			metadata,
		)
		return err
	})
	return response, err
}

func appendRichLinkInRepository(
	ctx context.Context,
	repo Repository,
	noteID pgtype.UUID,
	userID pgtype.UUID,
	operationID string,
	metadata map[string]any,
) (AppendRichLinkResponse, error) {
	if err := repo.EnsureNote(ctx, noteID, userID); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("ensure note: %w", err)
	}

	locked, err := repo.LockNote(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return AppendRichLinkResponse{}, ErrNoteNotFound
		}
		return AppendRichLinkResponse{}, fmt.Errorf("lock note: %w", err)
	}

	permission, err := repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("check permission: %w", err)
	}
	if permission != "owner" && permission != "edit" {
		return AppendRichLinkResponse{}, ErrNoPermission
	}

	opID := mustParseUUID(operationID)
	if existing, err := repo.GetNoteOperationByOpID(ctx, noteID, opID); err == nil {
		return AppendRichLinkResponse{
			Revision:        existing.Revision,
			Document:        locked.Document,
			AlreadyAccepted: true,
		}, nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return AppendRichLinkResponse{}, fmt.Errorf("dedup check: %w", err)
	}

	doc, err := UnmarshalDocument(locked.Document)
	if err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("unmarshal document: %w", err)
	}
	if len(doc.Blocks) == 0 {
		return AppendRichLinkResponse{}, fmt.Errorf("document has no blocks")
	}

	blockID := "rich-link-" + operationID
	payload, err := json.Marshal(CreateBlockPayload{
		ID:           blockID,
		Type:         string(BlockRichLink),
		Delta:        []delta.Op{},
		Metadata:     metadata,
		AfterBlockID: doc.Blocks[len(doc.Blocks)-1].ID,
	})
	if err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("marshal rich link: %w", err)
	}
	opRequest := OperationRequest{
		OperationID:  operationID,
		BaseRevision: locked.Revision,
		Kind:         string(KindCreateBlock),
		BlockID:      &blockID,
		Payload:      payload,
	}
	if err := validateAndTransform(ctx, repo, &opRequest, userID, opID, &doc, noteID, locked.Revision); err != nil {
		return AppendRichLinkResponse{}, err
	}
	if err := doc.ApplyOperation(KindCreateBlock, blockID, payload); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("apply rich link: %w", err)
	}

	revision := locked.Revision + 1
	if _, err := repo.InsertOperation(ctx, InsertOperationParams{
		NoteID:       noteID,
		Revision:     revision,
		OperationID:  opID,
		ActorID:      userID,
		BaseRevision: locked.Revision,
		Kind:         string(KindCreateBlock),
		BlockID:      pgtype.Text{String: blockID, Valid: true},
		Payload:      payload,
	}); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("insert rich link operation: %w", err)
	}

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("marshal document: %w", err)
	}
	if _, err := DecodeCanonicalDocument(docJSON); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("validate document: %w", err)
	}
	content, excerpt := DeriveContentFromDocument(doc)
	if err := repo.UpdateNoteDocument(ctx, UpdateNoteDocumentParams{
		NoteID:           noteID,
		Revision:         revision,
		Document:         docJSON,
		Content:          content,
		Excerpt:          excerpt,
		SnapshotRevision: revision,
	}); err != nil {
		return AppendRichLinkResponse{}, fmt.Errorf("update note document: %w", err)
	}

	return AppendRichLinkResponse{Revision: revision, Document: docJSON}, nil
}
