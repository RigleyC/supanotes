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

func (d *Document) ApplyOperation(kind Kind, blockID string, payload json.RawMessage) error {
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
		return d.applySetBlockMetadata(blockID, payload)
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

	targetID := blockID
	if targetID == "" {
		targetID = p.TaskID
	}
	if targetID == "" {
		return fmt.Errorf("missing taskId in complete task occurrence")
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == targetID {
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
			current := delta.New(d.Blocks[i].Delta)
			result := current.Compose(*incoming)
			d.Blocks[i].Delta = result.Ops
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

	d.Blocks = append(d.Blocks, newBlock)
	return nil
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

	var block Block
	removed := false
	for i, b := range d.Blocks {
		if b.ID == p.BlockID {
			block = b
			d.Blocks = append(d.Blocks[:i], d.Blocks[i+1:]...)
			removed = true
			break
		}
	}
	if !removed {
		return fmt.Errorf("%w: %s", ErrBlockNotFound, p.BlockID)
	}

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

	d.Blocks = append(d.Blocks, block)
	return nil
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

func (d *Document) applySetBlockMetadata(blockID string, payload json.RawMessage) error {
	var p SetBlockMetadataPayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return fmt.Errorf("parse set block metadata payload: %w", err)
	}

	for i := range d.Blocks {
		if d.Blocks[i].ID == blockID {
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
	if len(content) > 200 {
		excerpt = content[:200]
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
	var doc Document
	if err := json.Unmarshal(data, &doc); err != nil {
		return Document{}, err
	}
	if doc.SchemaVersion == 0 {
		doc.SchemaVersion = 1
	}
	return doc, nil
}

func NewEmptyDocument() Document {
	return Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{
				ID:       "init",
				Type:     string(BlockParagraph),
				Delta:    []delta.Op{{Insert: []rune("")}},
				Metadata: make(map[string]any),
			},
		},
	}
}
