package noteoperations

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type LockNoteResult struct {
	ID               pgtype.UUID `json:"id"`
	Revision         int64       `json:"revision"`
	Document         []byte      `json:"document"`
	SnapshotRevision int64       `json:"snapshot_revision"`
}

type GetNoteDocumentResult struct {
	Revision int64  `json:"revision"`
	Document []byte `json:"document"`
}

type InsertOperationParams struct {
	NoteID       pgtype.UUID     `json:"note_id"`
	Revision     int64           `json:"revision"`
	OperationID  pgtype.UUID     `json:"operation_id"`
	ActorID      pgtype.UUID     `json:"actor_id"`
	BaseRevision int64           `json:"base_revision"`
	Kind         string          `json:"kind"`
	BlockID      pgtype.Text     `json:"block_id"`
	Payload      json.RawMessage `json:"payload"`
}

type UpdateNoteDocumentParams struct {
	NoteID           pgtype.UUID `json:"note_id"`
	Revision         int64       `json:"revision"`
	Document         []byte      `json:"document"`
	Content          string      `json:"content"`
	Excerpt          string      `json:"excerpt"`
	SnapshotRevision int64       `json:"snapshot_revision"`
}

type Repository interface {
	EnsureNote(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) error
	LockNote(ctx context.Context, noteID pgtype.UUID) (LockNoteResult, error)
	InsertOperation(ctx context.Context, arg InsertOperationParams) (Operation, error)
	GetOperationsSince(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error)
	GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error)
	GetLastOperation(ctx context.Context, noteID pgtype.UUID) (Operation, error)
	UpdateNoteDocument(ctx context.Context, arg UpdateNoteDocumentParams) error
	GetNoteOperationByOpID(ctx context.Context, noteID pgtype.UUID, operationID pgtype.UUID) (Operation, error)
	CheckNotePermission(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error)
	GetNoteDocument(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error)
	WithQuerier(q sqlcgen.Querier) Repository
	WithTx(tx pgx.Tx) Repository
}

type repository struct {
	db   sqlcgen.DBTX
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) Repository {
	return &repository{db: pool, pool: pool}
}

const ensureNoteSQL = `INSERT INTO notes (id, user_id, content, excerpt, document, revision, snapshot_revision)
VALUES ($1, $2, '', NULL, $3, 0, 0)
ON CONFLICT (id) DO NOTHING`

func (r *repository) EnsureNote(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) error {
	document, err := json.Marshal(NewEmptyDocument())
	if err != nil {
		return err
	}
	_, err = r.db.Exec(ctx, ensureNoteSQL, noteID, userID, document)
	return err
}

func (r *repository) WithQuerier(_ sqlcgen.Querier) Repository {
	return r
}

func (r *repository) WithTx(tx pgx.Tx) Repository {
	return &repository{db: tx, pool: r.pool}
}

const lockNoteSQL = `SELECT id, revision, document, snapshot_revision FROM notes WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`

func (r *repository) LockNote(ctx context.Context, noteID pgtype.UUID) (LockNoteResult, error) {
	row := r.db.QueryRow(ctx, lockNoteSQL, noteID)
	var result LockNoteResult
	err := row.Scan(&result.ID, &result.Revision, &result.Document, &result.SnapshotRevision)
	if err != nil {
		return LockNoteResult{}, err
	}
	return result, nil
}

const insertOperationSQL = `INSERT INTO note_operations (note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at`

func (r *repository) InsertOperation(ctx context.Context, arg InsertOperationParams) (Operation, error) {
	row := r.db.QueryRow(ctx, insertOperationSQL,
		arg.NoteID, arg.Revision, arg.OperationID, arg.ActorID,
		arg.BaseRevision, arg.Kind, arg.BlockID, arg.Payload,
	)
	var op Operation
	err := row.Scan(
		&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
		&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
	)
	return op, err
}

const getOperationsSinceSQL = `SELECT note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at
FROM note_operations WHERE note_id = $1 AND revision > $2 ORDER BY revision`

func (r *repository) GetOperationsSince(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error) {
	rows, err := r.db.Query(ctx, getOperationsSinceSQL, noteID, afterRevision)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ops []Operation
	for rows.Next() {
		var op Operation
		if err := rows.Scan(
			&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
			&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
		); err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}

const getOperationsRangeSQL = `SELECT note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at
FROM note_operations WHERE note_id = $1 AND revision > $2 AND revision <= $3 ORDER BY revision`

func (r *repository) GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
	rows, err := r.db.Query(ctx, getOperationsRangeSQL, noteID, afterRevision, upToRevision)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ops []Operation
	for rows.Next() {
		var op Operation
		if err := rows.Scan(
			&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
			&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
		); err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}

const getLastOperationSQL = `SELECT note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at
FROM note_operations WHERE note_id = $1 ORDER BY revision DESC LIMIT 1`

func (r *repository) GetLastOperation(ctx context.Context, noteID pgtype.UUID) (Operation, error) {
	row := r.db.QueryRow(ctx, getLastOperationSQL, noteID)
	var op Operation
	err := row.Scan(
		&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
		&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
	)
	return op, err
}

const updateNoteDocumentSQL = `UPDATE notes SET document = $2, revision = $3, content = $4, excerpt = $5, snapshot_revision = $6, updated_at = NOW()
WHERE id = $1 AND deleted_at IS NULL`

func (r *repository) UpdateNoteDocument(ctx context.Context, arg UpdateNoteDocumentParams) error {
	_, err := r.db.Exec(ctx, updateNoteDocumentSQL,
		arg.NoteID, arg.Document, arg.Revision, arg.Content, arg.Excerpt, arg.SnapshotRevision,
	)
	return err
}

const getNoteOperationByOpIDSQL = `SELECT note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload, created_at
FROM note_operations WHERE note_id = $1 AND operation_id = $2`

func (r *repository) GetNoteOperationByOpID(ctx context.Context, noteID pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
	row := r.db.QueryRow(ctx, getNoteOperationByOpIDSQL, noteID, operationID)
	var op Operation
	err := row.Scan(
		&op.NoteID, &op.Revision, &op.OperationID, &op.ActorID,
		&op.BaseRevision, &op.Kind, &op.BlockID, &op.Payload, &op.CreatedAt,
	)
	return op, err
}

const checkNotePermissionSQL = `SELECT COALESCE(
  (SELECT 'owner'::text FROM notes WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL),
  (SELECT permission::text FROM note_shares ns JOIN notes n ON n.id = ns.note_id WHERE ns.note_id = $1 AND ns.user_id = $2 AND n.deleted_at IS NULL),
  (SELECT 'not_found'::text FROM notes WHERE id = $1),
  'none'::text
) AS permission`

func (r *repository) CheckNotePermission(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error) {
	row := r.db.QueryRow(ctx, checkNotePermissionSQL, noteID, userID)
	var permission string
	err := row.Scan(&permission)
	if err != nil {
		return "", err
	}
	return permission, nil
}

const getNoteDocumentSQL = `SELECT revision, document FROM notes WHERE id = $1 AND deleted_at IS NULL`

func (r *repository) GetNoteDocument(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error) {
	row := r.db.QueryRow(ctx, getNoteDocumentSQL, noteID)
	var result GetNoteDocumentResult
	err := row.Scan(&result.Revision, &result.Document)
	if err != nil {
		return GetNoteDocumentResult{}, err
	}
	return result, nil
}
