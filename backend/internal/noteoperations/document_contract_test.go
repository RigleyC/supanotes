package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestApplySetBlockMetadata_preservesExplicitDeletions(t *testing.T) {
	doc := Document{
		Blocks: []Block{{
			ID:       "b1",
			Type:     string(BlockParagraph),
			Metadata: map[string]any{"dueDate": "2026-07-27", "hasTime": false},
		}},
	}

	err := doc.ApplyOperation(
		KindSetBlockMetadata,
		"b1",
		json.RawMessage(`{"metadata":{"dueDate":null,"hasTime":true}}`),
	)
	require.NoError(t, err)
	assert.NotContains(t, doc.Blocks[0].Metadata, "dueDate")
	assert.Equal(t, true, doc.Blocks[0].Metadata["hasTime"])
}

func TestApplyCompleteTaskOccurrence_updatesAndReopensOccurrence(t *testing.T) {
	doc := Document{
		Blocks: []Block{{
			ID:       "task-1",
			Type:     string(BlockTask),
			Metadata: map[string]any{"completions": map[string]any{}},
		}},
	}
	complete := json.RawMessage(`{"taskId":"task-1","scheduledAt":"2026-07-27T09:00:00.000","completedAt":"2026-07-27T10:00:00.000Z"}`)
	reopen := json.RawMessage(`{"taskId":"task-1","scheduledAt":"2026-07-27T09:00:00.000","completedAt":null}`)

	require.NoError(t, doc.ApplyOperation(KindCompleteTaskOccurrence, "task-1", complete))
	completions := doc.Blocks[0].Metadata["completions"].(map[string]any)
	assert.Equal(t, "2026-07-27T10:00:00.000Z", completions["2026-07-27T09:00:00.000"])

	require.NoError(t, doc.ApplyOperation(KindCompleteTaskOccurrence, "task-1", reopen))
	assert.Empty(t, completions)
}
