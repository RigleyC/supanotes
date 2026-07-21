package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewEmptyDocument(t *testing.T) {
	doc := NewEmptyDocument()
	assert.Equal(t, 1, doc.SchemaVersion)
	assert.Len(t, doc.Blocks, 1)
	assert.Equal(t, "init", doc.Blocks[0].ID)
	assert.Equal(t, string(BlockParagraph), doc.Blocks[0].Type)
}

func TestUnmarshalDocument(t *testing.T) {
	jsonData := `{"schemaVersion":1,"blocks":[{"id":"b1","type":"paragraph","delta":[{"insert":"hello"}],"metadata":{}}]}`
	doc, err := UnmarshalDocument([]byte(jsonData))
	require.NoError(t, err)
	assert.Equal(t, 1, doc.SchemaVersion)
	assert.Len(t, doc.Blocks, 1)
	assert.Equal(t, "b1", doc.Blocks[0].ID)

	text := deltaText(doc.Blocks[0].Delta)
	assert.Equal(t, "hello", text)
}

func TestUnmarshalDocumentDefaultsSchemaVersion(t *testing.T) {
	jsonData := `{"blocks":[{"id":"b1","type":"paragraph","delta":[{"insert":"hi"}],"metadata":{}}]}`
	doc, err := UnmarshalDocument([]byte(jsonData))
	require.NoError(t, err)
	assert.Equal(t, 1, doc.SchemaVersion)
}

func TestDocumentMarshalRoundTrip(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{
				ID:   "b1",
				Type: string(BlockParagraph),
				Delta: []delta.Op{
					{Insert: []rune("Hello ")},
					{Insert: []rune("world"), Attributes: map[string]interface{}{"bold": true}},
				},
				Metadata: map[string]any{},
			},
		},
	}

	data, err := json.Marshal(doc)
	require.NoError(t, err)

	var decoded Document
	err = json.Unmarshal(data, &decoded)
	require.NoError(t, err)

	assert.Equal(t, doc.SchemaVersion, decoded.SchemaVersion)
	assert.Len(t, decoded.Blocks, 1)
	assert.Equal(t, "b1", decoded.Blocks[0].ID)
	text := deltaText(decoded.Blocks[0].Delta)
	assert.Equal(t, "Hello world", text)
}

func TestApplyTextDelta(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("hello")}}, Metadata: map[string]any{}},
		},
	}

	payload, _ := json.Marshal(struct {
		Ops []delta.Op `json:"ops"`
	}{Ops: []delta.Op{{Retain: intPtr(5)}, {Insert: []rune(" world")}}})

	err := doc.ApplyOperation(KindTextDelta, "b1", payload)
	require.NoError(t, err)

	text := deltaText(doc.Blocks[0].Delta)
	assert.Equal(t, "hello world", text)
}

func TestApplyTextDeltaBlockNotFound(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(struct {
		Ops []delta.Op `json:"ops"`
	}{Ops: []delta.Op{{Insert: []rune("test")}}})

	err := doc.ApplyOperation(KindTextDelta, "nonexistent", payload)
	assert.ErrorIs(t, err, ErrBlockNotFound)
}

func TestApplyCreateBlock(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(CreateBlockPayload{
		ID:           "b2",
		Type:         string(BlockParagraph),
		Delta:        []delta.Op{{Insert: []rune("new block")}},
		AfterBlockID: "init",
	})

	err := doc.ApplyOperation(KindCreateBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 2)
	assert.Equal(t, "b2", doc.Blocks[1].ID)
}

func TestApplyCreateBlockPrependBeginning(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(CreateBlockPayload{
		ID:    "b2",
		Type:  string(BlockParagraph),
		Delta: []delta.Op{{Insert: []rune("beginning")}},
	})

	err := doc.ApplyOperation(KindCreateBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 2)
	assert.Equal(t, "b2", doc.Blocks[0].ID)
}

func TestApplyCreateBlockAnchorNotFound(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(CreateBlockPayload{
		ID:           "b2",
		Type:         string(BlockParagraph),
		AfterBlockID: "nonexistent",
	})

	err := doc.ApplyOperation(KindCreateBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 2)
}

func TestApplyDeleteBlock(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}

	err := doc.ApplyOperation(KindDeleteBlock, "b1", nil)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 1)
	assert.Equal(t, "b2", doc.Blocks[0].ID)
}

func TestApplyDeleteBlockNotFound(t *testing.T) {
	doc := NewEmptyDocument()
	err := doc.ApplyOperation(KindDeleteBlock, "nonexistent", nil)
	assert.ErrorIs(t, err, ErrBlockNotFound)
}

func TestApplyMoveBlock(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Metadata: map[string]any{}},
			{ID: "b3", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}

	payload, _ := json.Marshal(MoveBlockPayload{BlockID: "b1", AfterBlockID: "b3"})
	err := doc.ApplyOperation(KindMoveBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 3)
	assert.Equal(t, "b2", doc.Blocks[0].ID)
	assert.Equal(t, "b3", doc.Blocks[1].ID)
	assert.Equal(t, "b1", doc.Blocks[2].ID)
}

func TestApplyMoveBlockToBeginning(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}

	payload, _ := json.Marshal(MoveBlockPayload{BlockID: "b2", AfterBlockID: ""})
	err := doc.ApplyOperation(KindMoveBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 2)
	assert.Equal(t, "b2", doc.Blocks[0].ID)
	assert.Equal(t, "b1", doc.Blocks[1].ID)
}

func TestApplySetBlockType(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}

	payload, _ := json.Marshal(SetBlockTypePayload{Type: string(BlockHeader1)})
	err := doc.ApplyOperation(KindSetBlockType, "b1", payload)
	require.NoError(t, err)
	assert.Equal(t, string(BlockHeader1), doc.Blocks[0].Type)
}

func TestDeriveContentFromDocument(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockHeader1), Delta: []delta.Op{{Insert: []rune("Title")}}, Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("Some content")}}, Metadata: map[string]any{}},
			{ID: "b3", Type: string(BlockQuote), Delta: []delta.Op{{Insert: []rune("A quote")}}, Metadata: map[string]any{}},
		},
	}

	content, excerpt := DeriveContentFromDocument(doc)
	assert.Contains(t, content, "# Title")
	assert.Contains(t, content, "Some content")
	assert.Contains(t, content, "> A quote")
	assert.Equal(t, content, excerpt)
}

func TestDeriveContentExcerptTruncated(t *testing.T) {
	longText := ""
	for i := 0; i < 50; i++ {
		longText += "Lorem ipsum dolor sit amet. "
	}
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune(longText)}}, Metadata: map[string]any{}},
		},
	}

	_, excerpt := DeriveContentFromDocument(doc)
	assert.LessOrEqual(t, len(excerpt), 200)
}

func TestApplyInvalidKind(t *testing.T) {
	doc := NewEmptyDocument()
	err := doc.ApplyOperation("invalid_kind", "", nil)
	assert.ErrorIs(t, err, ErrInvalidOperationKind)
}

func TestDeltaText(t *testing.T) {
	ops := []delta.Op{
		{Insert: []rune("Hello ")},
		{Delete: intPtr(3)},
		{Insert: []rune("world"), Attributes: map[string]interface{}{"bold": true}},
	}
	text := deltaText(ops)
	assert.Equal(t, "Hello world", text)
}

func intPtr(i int) *int { return &i }
