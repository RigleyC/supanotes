package noteoperations

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/fmpwizard/go-quilljs-delta/delta"
)

var (
	ErrNoteNotFound = errors.New("note not found")
	ErrNoPermission = errors.New("no permission")
)

type Service struct {
	repo Repository
	pool *pgxpool.Pool
}

func NewService(repo Repository, pool *pgxpool.Pool) *Service {
	return &Service{repo: repo, pool: pool}
}

func (s *Service) SyncOperations(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, req SyncRequest) (SyncResponse, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return SyncResponse{}, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	txRepo := s.repo.WithTx(tx)

	locked, err := txRepo.LockNote(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return SyncResponse{}, ErrNoteNotFound
		}
		return SyncResponse{}, fmt.Errorf("lock note: %w", err)
	}

	perm, err := txRepo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return SyncResponse{}, fmt.Errorf("check permission: %w", err)
	}
	if perm != "owner" && perm != "edit" {
		return SyncResponse{}, ErrNoPermission
	}

	doc, err := UnmarshalDocument(locked.Document)
	if err != nil {
		return SyncResponse{}, fmt.Errorf("unmarshal document: %w", err)
	}

	currentRevision := locked.Revision
	var accepted []AcceptedOperation

	for _, opReq := range req.Operations {
		opID := mustParseUUID(opReq.OperationID)

		dedupOp, err := txRepo.GetNoteOperationByOpID(ctx, noteID, opID)
		if err == nil {
			accepted = append(accepted, AcceptedOperation{
				OperationID: opReq.OperationID,
				Revision:    dedupOp.Revision,
				Kind:        dedupOp.Kind,
				BlockID:     blockIDToString(dedupOp.BlockID),
			})
			continue
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return SyncResponse{}, fmt.Errorf("dedup check: %w", err)
		}

		if err := validateAndTransform(ctx, txRepo, &opReq, &doc, noteID, currentRevision); err != nil {
			return SyncResponse{}, err
		}

		if err := doc.ApplyOperation(Kind(opReq.Kind), ptrStr(opReq.BlockID), opReq.Payload); err != nil {
			return SyncResponse{}, fmt.Errorf("apply operation: %w", err)
		}

		currentRevision++

		var blockID pgtype.Text
		if opReq.BlockID != nil {
			blockID = pgtype.Text{String: *opReq.BlockID, Valid: true}
		}

		_, err = txRepo.InsertOperation(ctx, InsertOperationParams{
			NoteID:       noteID,
			Revision:     currentRevision,
			OperationID:  opID,
			ActorID:      userID,
			BaseRevision: opReq.BaseRevision,
			Kind:         opReq.Kind,
			BlockID:      blockID,
			Payload:      opReq.Payload,
		})
		if err != nil {
			return SyncResponse{}, fmt.Errorf("insert operation: %w", err)
		}

		accepted = append(accepted, AcceptedOperation{
			OperationID: opReq.OperationID,
			Revision:    currentRevision,
			Kind:        opReq.Kind,
			BlockID:     ptrStr(opReq.BlockID),
		})
	}

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return SyncResponse{}, fmt.Errorf("marshal document: %w", err)
	}

	content, excerpt := DeriveContentFromDocument(doc)
	if err := txRepo.UpdateNoteDocument(ctx, UpdateNoteDocumentParams{
		NoteID:           noteID,
		Revision:         currentRevision,
		Document:         docJSON,
		Content:          content,
		Excerpt:          excerpt,
		SnapshotRevision: currentRevision,
	}); err != nil {
		return SyncResponse{}, fmt.Errorf("update note document: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return SyncResponse{}, fmt.Errorf("commit tx: %w", err)
	}

	remoteOps, err := s.repo.GetOperationsSince(ctx, noteID, req.KnownRevision)
	if err != nil {
		return SyncResponse{}, fmt.Errorf("fetch remote ops: %w", err)
	}

	acceptedSet := make(map[string]bool, len(accepted))
	for _, a := range accepted {
		acceptedSet[a.OperationID] = true
	}

	var filteredRemote []Operation
	for _, op := range remoteOps {
		if !acceptedSet[opIDToString(op.OperationID)] {
			filteredRemote = append(filteredRemote, op)
		}
	}

	return SyncResponse{
		Accepted:         accepted,
		FinalRevision:    currentRevision,
		RemoteOperations: filteredRemote,
		ServerTime:       time.Now().UTC(),
	}, nil
}

func validateAndTransform(
	ctx context.Context,
	txRepo Repository,
	opReq *OperationRequest,
	doc *Document,
	noteID pgtype.UUID,
	currentRevision int64,
) error {
	if err := ValidateOperation(*opReq, *doc, opReq.BaseRevision); err != nil {
		return err
	}

	if opReq.BaseRevision < currentRevision && opReq.Kind == string(KindTextDelta) {
		concurrentOps, err := txRepo.GetOperationsSince(ctx, noteID, opReq.BaseRevision)
		if err != nil {
			return fmt.Errorf("fetch concurrent ops: %w", err)
		}

		clientDelta, err := delta.FromJSON(opReq.Payload)
		if err != nil {
			return fmt.Errorf("parse client delta: %w", err)
		}

		for _, co := range concurrentOps {
			if co.Kind != string(KindTextDelta) || !co.BlockID.Valid || co.BlockID.String != ptrStr(opReq.BlockID) {
				continue
			}

			serverDelta, err := delta.FromJSON(co.Payload)
			if err != nil {
				return fmt.Errorf("parse concurrent delta: %w", err)
			}

			clientDelta = serverDelta.Transform(*clientDelta, false)
		}

		transformedPayload, err := json.Marshal(clientDelta)
		if err != nil {
			return fmt.Errorf("marshal transformed delta: %w", err)
		}
		opReq.Payload = transformedPayload
	}

	return nil
}

func (s *Service) GetDocument(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (DocumentResponse, error) {
	perm, err := s.repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return DocumentResponse{}, fmt.Errorf("check permission: %w", err)
	}
	if perm != "owner" && perm != "edit" && perm != "view" {
		return DocumentResponse{}, ErrNoPermission
	}

	result, err := s.repo.GetNoteDocument(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return DocumentResponse{}, ErrNoteNotFound
		}
		return DocumentResponse{}, fmt.Errorf("get document: %w", err)
	}

	return DocumentResponse{
		NoteID:     pgtypeUUIDToString(noteID),
		Revision:   result.Revision,
		Document:   result.Document,
		ServerTime: time.Now().UTC(),
	}, nil
}

func (s *Service) GetOperationsSince(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, afterRevision int64) (OperationsListResponse, error) {
	perm, err := s.repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("check permission: %w", err)
	}
	if perm != "owner" && perm != "edit" && perm != "view" {
		return OperationsListResponse{}, ErrNoPermission
	}

	ops, err := s.repo.GetOperationsSince(ctx, noteID, afterRevision)
	if err != nil {
		return OperationsListResponse{}, fmt.Errorf("get operations: %w", err)
	}

	return OperationsListResponse{Operations: ops}, nil
}

func mustParseUUID(s string) pgtype.UUID {
	id, err := uuid.Parse(s)
	if err != nil {
		return pgtype.UUID{}
	}
	return pgtype.UUID{Bytes: id, Valid: true}
}

func ptrStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func blockIDToString(blockID pgtype.Text) string {
	if blockID.Valid {
		return blockID.String
	}
	return ""
}

func opIDToString(opID pgtype.UUID) string {
	if !opID.Valid {
		return ""
	}
	return uuid.UUID(opID.Bytes).String()
}

func pgtypeUUIDToString(u pgtype.UUID) string {
	if !u.Valid {
		return ""
	}
	return uuid.UUID(u.Bytes).String()
}
