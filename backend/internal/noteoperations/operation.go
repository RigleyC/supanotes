package noteoperations

import (
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/fmpwizard/go-quilljs-delta/delta"
)

type Kind string

const (
	KindTextDelta        Kind = "text_delta"
	KindCreateBlock      Kind = "create_block"
	KindDeleteBlock      Kind = "delete_block"
	KindMoveBlock        Kind = "move_block"
	KindSetBlockType     Kind = "set_block_type"
	KindSetBlockMetadata       Kind = "set_block_metadata"
	KindCompleteTaskOccurrence Kind = "complete_task_occurrence"
)

var ValidKinds = map[Kind]bool{
	KindTextDelta:              true,
	KindCreateBlock:            true,
	KindDeleteBlock:            true,
	KindMoveBlock:              true,
	KindSetBlockType:           true,
	KindSetBlockMetadata:       true,
	KindCompleteTaskOccurrence: true,
}

type CompleteTaskOccurrencePayload struct {
	TaskID      string  `json:"taskId"`
	ScheduledAt string  `json:"scheduledAt"`
	CompletedAt *string `json:"completedAt"`
}

type BlockType string

const (
	BlockParagraph   BlockType = "paragraph"
	BlockHeader1     BlockType = "header1"
	BlockHeader2     BlockType = "header2"
	BlockHeader3     BlockType = "header3"
	BlockQuote       BlockType = "quote"
	BlockBulletList  BlockType = "bulletList"
	BlockOrderedList BlockType = "orderedList"
	BlockDivider     BlockType = "divider"
	BlockTask        BlockType = "task"
	BlockAttachment  BlockType = "attachment"
	BlockRichLink    BlockType = "rich_link"
)

var ValidBlockTypes = map[BlockType]bool{
	BlockParagraph:   true,
	BlockHeader1:     true,
	BlockHeader2:     true,
	BlockHeader3:     true,
	BlockQuote:       true,
	BlockBulletList:  true,
	BlockOrderedList: true,
	BlockDivider:     true,
	BlockTask:        true,
	BlockAttachment:  true,
	BlockRichLink:    true,
}

type Operation struct {
	NoteID       pgtype.UUID        `json:"noteId"`
	Revision     int64              `json:"revision"`
	OperationID  pgtype.UUID        `json:"operationId"`
	ActorID      pgtype.UUID        `json:"actorId"`
	BaseRevision int64              `json:"baseRevision"`
	Kind         string             `json:"kind"`
	BlockID      pgtype.Text        `json:"blockId"`
	Payload      json.RawMessage    `json:"payload"`
	CreatedAt    pgtype.Timestamptz `json:"createdAt"`
}

type OperationRequest struct {
	OperationID  string          `json:"operationId" validate:"required,uuid"`
	BaseRevision int64           `json:"baseRevision" validate:"min=0"`
	Kind         string          `json:"kind" validate:"required"`
	BlockID      *string         `json:"blockId,omitempty"`
	Payload      json.RawMessage `json:"payload"`
}

type SyncRequest struct {
	KnownRevision int64              `json:"knownRevision" validate:"min=0"`
	Operations    []OperationRequest `json:"operations" validate:"dive"`
	ClientID      string             `json:"clientId"`
}

type AcceptedOperation struct {
	OperationID string `json:"operationId"`
	Revision    int64  `json:"revision"`
	Kind        string `json:"kind"`
	BlockID     string `json:"blockId"`
}

type SyncResponse struct {
	Accepted          []AcceptedOperation `json:"accepted"`
	FinalRevision     int64               `json:"finalRevision"`
	RemoteOperations  []Operation         `json:"remoteOperations"`
	CanonicalDocument json.RawMessage     `json:"canonicalDocument"`
	ServerTime        time.Time           `json:"serverTime"`
}

type DocumentResponse struct {
	NoteID     string          `json:"noteId"`
	Revision   int64           `json:"revision"`
	Document   json.RawMessage `json:"document"`
	ServerTime time.Time       `json:"serverTime"`
}

type OperationsListResponse struct {
	Operations []Operation      `json:"operations"`
	Document   json.RawMessage  `json:"document,omitempty"`
	Revision   int64            `json:"revision,omitempty"`
}

func parseDeltaFromPayload(payload json.RawMessage) (*delta.Delta, error) {
	var p struct {
		Ops []delta.Op `json:"ops"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		return nil, err
	}
	return delta.New(p.Ops), nil
}

func parseCreateBlockPayload(payload json.RawMessage) (*CreateBlockPayload, error) {
	var p CreateBlockPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func parseMoveBlockPayload(payload json.RawMessage) (*MoveBlockPayload, error) {
	var p MoveBlockPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func parseSetBlockTypePayload(payload json.RawMessage) (*SetBlockTypePayload, error) {
	var p SetBlockTypePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return nil, err
	}
	return &p, nil
}
