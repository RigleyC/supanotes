package noteoperations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
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

func TestApplyTextDeltaRecoversMissingBlock(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{{
			ID:       "existing",
			Type:     string(BlockParagraph),
			Delta:    []delta.Op{{Insert: []rune("")}},
			Metadata: map[string]any{},
		}},
	}
	payload, _ := json.Marshal(struct {
		Ops []delta.Op `json:"ops"`
	}{Ops: []delta.Op{{Insert: []rune("test")}}})

	err := doc.ApplyOperation(KindTextDelta, "nonexistent", payload)
	require.NoError(t, err)
	assert.Equal(t, "nonexistent", doc.Blocks[1].ID)
	assert.Equal(t, "test", deltaText(doc.Blocks[1].Delta))
}

func TestApplyTextDeltaAdoptsFirstLocalBlockID(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(struct {
		Ops []delta.Op `json:"ops"`
	}{Ops: []delta.Op{{Insert: []rune("test")}}})

	err := doc.ApplyOperation(KindTextDelta, "local-block", payload)
	require.NoError(t, err)
	assert.Equal(t, "local-block", doc.Blocks[0].ID)
	assert.Equal(t, "test", deltaText(doc.Blocks[0].Delta))
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

func TestApplySharedCreateBlockContractFixture(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	fixturePath := filepath.Join(filepath.Dir(currentFile), "../../../test/fixtures/ot_create_blocks_contract.json")
	data, err := os.ReadFile(fixturePath)
	require.NoError(t, err)

	var fixture struct {
		Blocks []CreateBlockPayload `json:"blocks"`
	}
	require.NoError(t, json.Unmarshal(data, &fixture))

	doc := NewEmptyDocument()
	for _, block := range fixture.Blocks {
		payload, err := json.Marshal(block)
		require.NoError(t, err)
		require.NoError(t, doc.ApplyOperation(KindCreateBlock, block.ID, payload))
	}

	for _, expected := range fixture.Blocks {
		var actual *Block
		for i := range doc.Blocks {
			if doc.Blocks[i].ID == expected.ID {
				actual = &doc.Blocks[i]
				break
			}
		}
		require.NotNil(t, actual, expected.ID)
		assert.Equal(t, expected.Type, actual.Type)
		assert.Equal(t, deltaText(expected.Delta), deltaText(actual.Delta))
		expectedMetadata := expected.Metadata
		if expectedMetadata == nil {
			expectedMetadata = map[string]any{}
		}
		assert.Equal(t, expectedMetadata, actual.Metadata)
	}
}

func TestApplyCreateBlockIsIdempotentForExistingBlockID(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{{
			ID:       "b1",
			Type:     string(BlockTask),
			Delta:    []delta.Op{{Insert: []rune("local text")}},
			Metadata: map[string]any{},
		}},
	}
	payload, _ := json.Marshal(CreateBlockPayload{
		ID:    "b1",
		Type:  string(BlockParagraph),
		Delta: []delta.Op{{Insert: []rune("stale text")}},
	})

	err := doc.ApplyOperation(KindCreateBlock, "b1", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 1)
	assert.Equal(t, "local text", deltaText(doc.Blocks[0].Delta))
}

func TestUnmarshalDocumentRemovesDuplicateBlockIDs(t *testing.T) {
	doc, err := UnmarshalDocument([]byte(`{
		"blocks":[
			{"id":"b1","type":"task","delta":[{"insert":"current"}],"metadata":{}},
			{"id":"b1","type":"paragraph","delta":[{"insert":"stale"}],"metadata":{}}
		]
	}`))

	require.NoError(t, err)
	require.Len(t, doc.Blocks, 1)
	assert.Equal(t, "current", deltaText(doc.Blocks[0].Delta))
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
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 1)
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

func TestApplyMoveBlockMissingBlockIsNoOp(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(MoveBlockPayload{BlockID: "missing"})

	err := doc.ApplyOperation(KindMoveBlock, "", payload)
	require.NoError(t, err)
	assert.Len(t, doc.Blocks, 1)
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

func TestApplySetBlockTypeRecoversMissingBlock(t *testing.T) {
	doc := NewEmptyDocument()
	payload, _ := json.Marshal(SetBlockTypePayload{Type: string(BlockTask)})

	err := doc.ApplyOperation(KindSetBlockType, "task-1", payload)
	require.NoError(t, err)
	assert.Equal(t, "task-1", doc.Blocks[0].ID)
	assert.Equal(t, string(BlockTask), doc.Blocks[0].Type)
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
