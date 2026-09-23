package noteoperations

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/fmpwizard/go-quilljs-delta/delta"
)

type Document struct {
	SchemaVersion int     `json:"schemaVersion"`
	Blocks        []Block `json:"blocks"`
}

type Block struct {
	ID       string         `json:"id"`
	Type     string         `json:"type"`
	Delta    []delta.Op     `json:"delta"`
	Metadata map[string]any `json:"metadata"`
}

type TextDeltaPayload struct {
	Ops []delta.Op `json:"ops"`
}

type CreateBlockPayload struct {
	ID           string         `json:"id"`
	Type         string         `json:"type"`
	Delta        []delta.Op     `json:"delta"`
	Metadata     map[string]any `json:"metadata"`
	AfterBlockID string         `json:"afterBlockId"`
}

type MoveBlockPayload struct {
	BlockID      string `json:"blockId"`
	AfterBlockID string `json:"afterBlockId"`
}

type SetBlockTypePayload struct {
	Type string `json:"type"`
}

var ErrBlockNotFound = fmt.Errorf("block not found")
var ErrInvalidOperationKind = fmt.Errorf("invalid operation kind")

const InitialBlockID = "init"

func (d *Document) ApplyOperation(kind Kind, blockID string, payload json.RawMessage) error {
	return d.applyOperation(kind, blockID, payload, nil)
}

func (d *Document) ApplyOperationWithCompletionEvidence(
	kind Kind,
	blockID string,
	payload json.RawMessage,
	evidence []taskCompletionHistoryRecord,
) error {
	return d.applyOperation(kind, blockID, payload, evidence)
}

func (d *Document) applyOperation(
	kind Kind,
	blockID string,
	payload json.RawMessage,
	evidence []taskCompletionHistoryRecord,
) error {
	switch kind {
	case KindTextDelta:
		return d.applyTextDelta(blockID, payload)
	case KindCreateBlock:
		return d.applyCreateBlock(payload)
	case KindDeleteBlock:
		return d.applyDeleteBlock(blockID)
	case KindMoveBlock:
		return d.applyMoveBlock(payload)
	case KindSetBlockType:
		return d.applySetBlockType(blockID, payload)
	case KindSetBlockMetadata:
		return d.applySetBlockMetadata(blockID, payload, evidence)
	case KindCompleteTaskOccurrence:
		return d.applyCompleteTaskOccurrence(blockID, payload)
	default:
		return ErrInvalidOperationKind
	}
}

func (d *Document) applyCompleteTaskOccurrence(blockID string, payload json.RawMessage) error {
	var p CompleteTaskOccurrencePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return fmt.Errorf("parse complete task occurrence payload: %w", err)
	}
	if p.TaskID == "" || strings.TrimSpace(p.ScheduledAt) == "" {
		return fmt.Errorf("complete task occurrence requires taskId and scheduledAt")
	}
	if p.CompletedAt != nil && strings.TrimSpace(*p.CompletedAt) == "" {
		return fmt.Errorf("complete task occurrence completedAt must be null or non-empty")
	}
	if blockID != "" && blockID != p.TaskID {
		return fmt.Errorf("complete task occurrence blockID does not match taskId")
	}

	targetID := blockID
	if targetID == "" {
		targetID = p.TaskID
	}
	if targetID == "" {
		return fmt.Errorf("missing taskId in complete task occurrence")
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == targetID {
			if d.Blocks[i].Type != string(BlockTask) {
				return fmt.Errorf("complete task occurrence requires a task block")
			}
			if d.Blocks[i].Metadata == nil {
				d.Blocks[i].Metadata = make(map[string]any)
			}
			completions, ok := d.Blocks[i].Metadata["completions"].(map[string]any)
			if !ok {
				completions = make(map[string]any)
			}
			if p.CompletedAt != nil && *p.CompletedAt != "" {
				completions[p.ScheduledAt] = *p.CompletedAt
			} else {
				delete(completions, p.ScheduledAt)
			}
			d.Blocks[i].Metadata["completions"] = completions
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrBlockNotFound, targetID)
}

func (d *Document) applyTextDelta(blockID string, payload json.RawMessage) error {
	incoming, err := parseDeltaFromPayload(payload)
	if err != nil {
		return fmt.Errorf("parse text delta payload: %w", err)
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == blockID {
			currentOps, err := normalizeDocumentDelta(d.Blocks[i].Delta, d.Blocks[i].ID)
			if err != nil {
				return err
			}
			current := delta.New(opsToUTF16(currentOps))
			result := current.Compose(*incoming)
			normalized, err := normalizeDocumentDelta(result.Ops, d.Blocks[i].ID)
			if err != nil {
				return err
			}
			d.Blocks[i].Delta = opsFromUTF16(normalized)
			return nil
		}
	}

	return fmt.Errorf("%w: %s", ErrBlockNotFound, blockID)
}

func (d *Document) applyCreateBlock(payload json.RawMessage) error {
	p, err := parseCreateBlockPayload(payload)
	if err != nil {
		return fmt.Errorf("parse create block payload: %w", err)
	}
	for _, block := range d.Blocks {
		if block.ID == p.ID {
			return nil
		}
	}

	meta := p.Metadata
	if meta == nil {
		meta = make(map[string]any)
	}

	newBlock := Block{
		ID:       p.ID,
		Type:     p.Type,
		Delta:    p.Delta,
		Metadata: meta,
	}

	if p.AfterBlockID == "" {
		d.Blocks = append([]Block{newBlock}, d.Blocks...)
		return nil
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == p.AfterBlockID {
			d.Blocks = append(d.Blocks[:i+1], append([]Block{newBlock}, d.Blocks[i+1:]...)...)
			return nil
		}
	}

	return fmt.Errorf("%w: %s", ErrInvalidAnchor, p.AfterBlockID)
}

func (d *Document) applyDeleteBlock(blockID string) error {
	for i, b := range d.Blocks {
		if b.ID == blockID {
			d.Blocks = append(d.Blocks[:i], d.Blocks[i+1:]...)
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrBlockNotFound, blockID)
}

func (d *Document) applyMoveBlock(payload json.RawMessage) error {
	p, err := parseMoveBlockPayload(payload)
	if err != nil {
		return fmt.Errorf("parse move block payload: %w", err)
	}

	if p.BlockID == p.AfterBlockID {
		return fmt.Errorf("%w: block cannot be its own anchor", ErrInvalidAnchor)
	}

	sourceIndex := -1
	for i, b := range d.Blocks {
		if b.ID == p.BlockID {
			sourceIndex = i
			break
		}
	}
	if sourceIndex < 0 {
		return fmt.Errorf("%w: %s", ErrBlockNotFound, p.BlockID)
	}

	if p.AfterBlockID != "" {
		anchorFound := false
		for _, b := range d.Blocks {
			if b.ID == p.AfterBlockID {
				anchorFound = true
				break
			}
		}
		if !anchorFound {
			return fmt.Errorf("%w: %s", ErrInvalidAnchor, p.AfterBlockID)
		}
	}

	block := d.Blocks[sourceIndex]
	d.Blocks = append(d.Blocks[:sourceIndex], d.Blocks[sourceIndex+1:]...)
	if p.AfterBlockID == "" {
		d.Blocks = append([]Block{block}, d.Blocks...)
		return nil
	}

	for i, b := range d.Blocks {
		if b.ID == p.AfterBlockID {
			d.Blocks = append(d.Blocks[:i+1], append([]Block{block}, d.Blocks[i+1:]...)...)
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrInvalidAnchor, p.AfterBlockID)
}

type SetBlockMetadataPayload struct {
	Metadata map[string]any `json:"metadata"`
}

func (d *Document) applySetBlockType(blockID string, payload json.RawMessage) error {
	p, err := parseSetBlockTypePayload(payload)
	if err != nil {
		return fmt.Errorf("parse set block type payload: %w", err)
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == blockID {
			d.Blocks[i].Type = p.Type
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrBlockNotFound, blockID)
}

func (d *Document) applySetBlockMetadata(
	blockID string,
	payload json.RawMessage,
	evidence []taskCompletionHistoryRecord,
) error {
	var p SetBlockMetadataPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return fmt.Errorf("parse set block metadata payload: %w", err)
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == blockID {
			if err := validateTaskScheduleMetadataTransition(d.Blocks[i], p.Metadata, evidence); err != nil {
				return err
			}
			if d.Blocks[i].Metadata == nil {
				d.Blocks[i].Metadata = make(map[string]any)
			}
			for k, v := range p.Metadata {
				if v == nil {
					delete(d.Blocks[i].Metadata, k)
				} else {
					d.Blocks[i].Metadata[k] = v
				}
			}
			return nil
		}
	}
	return fmt.Errorf("%w: %s", ErrBlockNotFound, blockID)
}

func DeriveContentFromDocument(doc Document) (content, excerpt string) {
	var parts []string
	for _, block := range doc.Blocks {
		text := deltaText(block.Delta)
		line := formatBlockAsMarkdown(block, text)
		if line != "" {
			parts = append(parts, line)
		}
	}
	content = strings.Join(parts, "\n")
	runes := []rune(content)
	if len(runes) > 200 {
		excerpt = string(runes[:200])
	} else {
		excerpt = content
	}
	return
}

func deltaText(ops []delta.Op) string {
	var b strings.Builder
	for _, op := range ops {
		if len(op.Insert) > 0 {
			b.WriteString(string(op.Insert))
		}
	}
	return b.String()
}

func formatBlockAsMarkdown(block Block, text string) string {
	text = strings.TrimSpace(text)
	if text == "" && block.Type != string(BlockDivider) {
		return ""
	}

	switch BlockType(block.Type) {
	case BlockHeader1:
		return "# " + text
	case BlockHeader2:
		return "## " + text
	case BlockHeader3:
		return "### " + text
	case BlockQuote:
		return "> " + text
	case BlockBulletList:
		return "- " + text
	case BlockOrderedList:
		return "1. " + text
	case BlockTask:
		isComp, _ := block.Metadata["isCompleted"].(bool)
		if isComp {
			return "- [x] " + text
		}
		return "- [ ] " + text
	case BlockDivider:
		return "---"
	default:
		return text
	}
}

func UnmarshalDocument(data []byte) (Document, error) {
	var envelope struct {
		SchemaVersion *int              `json:"schemaVersion"`
		Blocks        []json.RawMessage `json:"blocks"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return Document{}, err
	}
	if envelope.SchemaVersion == nil {
		return Document{}, fmt.Errorf("missing schemaVersion")
	}
	if *envelope.SchemaVersion != 1 {
		return Document{}, fmt.Errorf("unsupported schemaVersion %d", *envelope.SchemaVersion)
	}
	if len(envelope.Blocks) == 0 {
		return Document{}, fmt.Errorf("document has no blocks")
	}
	if err := validateCanonicalBlocks(envelope.Blocks); err != nil {
		return Document{}, err
	}

	var doc Document
	if err := json.Unmarshal(data, &doc); err != nil {
		return Document{}, err
	}
	seen := make(map[string]struct{}, len(doc.Blocks))
	for _, block := range doc.Blocks {
		if _, exists := seen[block.ID]; exists {
			return Document{}, fmt.Errorf("document contains duplicate block ids")
		}
		seen[block.ID] = struct{}{}
	}
	return doc, nil
}

// RepairDocument is reserved for explicit bootstrap or migration flows. REST/OT
// mutation and delivery paths must use UnmarshalDocument and reject malformed
// snapshots instead of repairing them implicitly.
func RepairDocument(data []byte) (Document, error) {
	var doc Document
	if err := json.Unmarshal(data, &doc); err != nil {
		return Document{}, err
	}
	if doc.SchemaVersion == 0 {
		doc.SchemaVersion = 1
	}
	if err := doc.normalizeDocumentDeltas(); err != nil {
		return Document{}, err
	}
	doc.removeDuplicateBlockIDs()
	if len(doc.Blocks) == 0 {
		doc = NewEmptyDocument()
	}
	return doc, nil
}

func (d *Document) normalizeDocumentDeltas() error {
	for blockIndex := range d.Blocks {
		block := &d.Blocks[blockIndex]
		operations, err := normalizeDocumentDelta(block.Delta, block.ID)
		if err != nil {
			return err
		}
		block.Delta = operations
	}
	return nil
}

// normalizeDocumentDelta keeps only content operations. A document snapshot
// is not an OT change: delete and retain operations must never be persisted in
// it. They are discarded here because the faulty compose path could publish
// those mutation operations in a snapshot.
func normalizeDocumentDelta(operations []delta.Op, blockID string) ([]delta.Op, error) {
	normalized := make([]delta.Op, 0, len(operations))
	for _, operation := range operations {
		if operation.IsNil() {
			continue
		}
		if operation.InsertEmbed != nil {
			return nil, fmt.Errorf(
				"document block %q contains an unsupported embedded delta operation",
				blockID,
			)
		}
		if operation.Insert != nil {
			normalized = append(normalized, operation)
			continue
		}
		if operation.Delete != nil || operation.Retain != nil {
			continue
		}
		return nil, fmt.Errorf(
			"document block %q contains an invalid delta operation",
			blockID,
		)
	}
	return normalized, nil
}

func (d *Document) removeDuplicateBlockIDs() {
	seen := make(map[string]struct{}, len(d.Blocks))
	blocks := d.Blocks[:0]
	for _, block := range d.Blocks {
		if _, exists := seen[block.ID]; exists {
			continue
		}
		seen[block.ID] = struct{}{}
		blocks = append(blocks, block)
	}
	d.Blocks = blocks
}

func NewEmptyDocument() Document {
	return Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{
				ID:       InitialBlockID,
				Type:     string(BlockParagraph),
				Delta:    plainTextDelta(""),
				Metadata: make(map[string]any),
			},
		},
	}
}

func plainTextDelta(content string) []delta.Op {
	if content == "" {
		return []delta.Op{}
	}
	return []delta.Op{{Insert: []rune(content)}}
}
