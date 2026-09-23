package noteoperations

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"

	"github.com/RigleyC/supanotes/internal/tasks"
)

// DecodeCanonicalDocument validates and decodes the schema-v1 snapshot shared
// by REST/OT, the public HTML reader, and native clients.
//
// UnmarshalDocument only accepts canonical snapshots. Explicit bootstrap or
// migration code that needs recovery must call RepairDocument directly.
func DecodeCanonicalDocument(data []byte) (Document, error) {
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

	document, err := UnmarshalDocument(data)
	if err != nil {
		return Document{}, err
	}
	if len(document.Blocks) != len(envelope.Blocks) {
		return Document{}, fmt.Errorf("document contains duplicate block ids")
	}
	return document, nil
}

func validateCanonicalBlocks(rawBlocks []json.RawMessage) error {
	for _, rawBlock := range rawBlocks {
		var block map[string]any
		if err := json.Unmarshal(rawBlock, &block); err != nil {
			return fmt.Errorf("invalid block: %w", err)
		}
		id, ok := block["id"].(string)
		if !ok || id == "" {
			return fmt.Errorf("block has no id")
		}
		blockType, ok := block["type"].(string)
		if !ok || !ValidBlockTypes[BlockType(blockType)] {
			return fmt.Errorf("unsupported block type %q", blockType)
		}
		delta, ok := block["delta"].([]any)
		if !ok {
			return fmt.Errorf("block %q has no delta", id)
		}
		for _, rawOperation := range delta {
			operation, ok := rawOperation.(map[string]any)
			if !ok {
				return fmt.Errorf("block %q contains an invalid delta", id)
			}
			if _, ok := operation["insert"].(string); !ok {
				return fmt.Errorf("block %q contains a non-text delta operation", id)
			}
			if attributes, ok := operation["attributes"]; ok && attributes != nil {
				if err := validateCanonicalDeltaAttributes(attributes, id); err != nil {
					return err
				}
			}
		}
		metadata, ok := block["metadata"]
		if !ok || metadata == nil {
			metadata = map[string]any{}
		}
		metadataMap, ok := metadata.(map[string]any)
		if !ok {
			return fmt.Errorf("block %q has invalid metadata", id)
		}
		if err := validateCanonicalBlockMetadata(blockType, metadataMap); err != nil {
			return fmt.Errorf("block %q: %w", id, err)
		}
	}
	return nil
}

func validateCanonicalDeltaAttributes(raw any, blockID string) error {
	attributes, ok := raw.(map[string]any)
	if !ok {
		return fmt.Errorf("block %q contains invalid delta attributes", blockID)
	}
	for key, value := range attributes {
		if key == "link" {
			link, ok := value.(string)
			if !ok {
				return fmt.Errorf("block %q contains an invalid link attribute", blockID)
			}
			if _, err := url.Parse(link); err != nil {
				return fmt.Errorf("block %q contains an invalid link attribute", blockID)
			}
			continue
		}
		if strings.HasPrefix(key, "link:") {
			if value != true {
				return fmt.Errorf("block %q contains an invalid link attribution", blockID)
			}
			if _, err := url.Parse(strings.TrimPrefix(key, "link:")); err != nil {
				return fmt.Errorf("block %q contains an invalid link attribution", blockID)
			}
		}
	}
	return nil
}

func validateCanonicalBlockMetadata(blockType string, metadata map[string]any) error {
	stringFields := map[string]bool{}
	boolFields := map[string]bool{}
	intFields := map[string]bool{}
	switch BlockType(blockType) {
	case BlockRichLink:
		for _, key := range []string{"url", "title", "description", "imageUrl", "domain"} {
			stringFields[key] = true
		}
	case BlockTask:
		for _, key := range []string{"isCompleted", "hasTime"} {
			boolFields[key] = true
		}
		for _, key := range []string{"dueDate", "recurrenceRule", "reminder", "lastCompletedAt"} {
			stringFields[key] = true
		}
		for _, key := range []string{"checked", "recurrence"} {
			if _, exists := metadata[key]; exists {
				return fmt.Errorf("legacy %s metadata is not allowed; run the task document backfill", key)
			}
		}
		intFields["indent"] = true
		if err := validateCanonicalTaskMetadata(metadata); err != nil {
			return err
		}
	case BlockBulletList, BlockOrderedList:
		intFields["indent"] = true
	case BlockAttachment:
		for _, key := range []string{"attachmentId", "filename", "mimeType", "url"} {
			stringFields[key] = true
		}
		intFields["fileSize"] = true
	}
	for key := range stringFields {
		if value, exists := metadata[key]; exists && value != nil {
			if _, ok := value.(string); !ok {
				return fmt.Errorf("invalid %s metadata", key)
			}
		}
	}
	for key := range boolFields {
		if value, exists := metadata[key]; exists && value != nil {
			if _, ok := value.(bool); !ok {
				return fmt.Errorf("invalid %s metadata", key)
			}
		}
	}
	for key := range intFields {
		if value, exists := metadata[key]; exists && value != nil {
			number, ok := value.(float64)
			if !ok || number != float64(int(number)) {
				return fmt.Errorf("invalid %s metadata", key)
			}
		}
	}
	return nil
}

func validateCanonicalTaskMetadata(metadata map[string]any) error {
	var dueDateValue, recurrenceValue, reminderValue *string
	if value, exists := metadata["dueDate"]; exists && value != nil {
		dueDate, ok := value.(string)
		if !ok || !isCanonicalScheduledAt(dueDate) {
			return fmt.Errorf("invalid dueDate metadata")
		}
		dueDateValue = &dueDate
	}

	if value, exists := metadata["recurrenceRule"]; exists && value != nil {
		recurrenceRule, ok := value.(string)
		if !ok || !tasks.IsCanonicalRecurrenceRule(recurrenceRule) {
			return fmt.Errorf("invalid recurrenceRule metadata")
		}
		recurrenceValue = &recurrenceRule
	}

	if value, exists := metadata["reminder"]; exists && value != nil {
		reminder, ok := value.(string)
		if !ok || !tasks.IsCanonicalReminder(reminder) {
			return fmt.Errorf("invalid reminder metadata")
		}
		reminderValue = &reminder
	}

	if !tasks.ValidScheduleMetadata(dueDateValue != nil, recurrenceValue, reminderValue) {
		return fmt.Errorf("recurrenceRule and reminder require dueDate metadata")
	}

	if value, exists := metadata["lastCompletedAt"]; exists && value != nil {
		lastCompletedAt, ok := value.(string)
		if !ok || !isCanonicalCompletedAt(lastCompletedAt) {
			return fmt.Errorf("invalid lastCompletedAt metadata")
		}
	}

	if value, exists := metadata["completions"]; exists && value != nil {
		completions, ok := value.(map[string]any)
		if !ok {
			return fmt.Errorf("invalid completions metadata")
		}
		for scheduledAt, rawCompletedAt := range completions {
			completedAt, ok := rawCompletedAt.(string)
			if !ok || !isCanonicalScheduledAt(scheduledAt) || !isCanonicalCompletedAt(completedAt) {
				return fmt.Errorf("invalid completions metadata")
			}
		}
	}

	if value, exists := metadata["completionHistory"]; exists && value != nil {
		records, ok := value.([]any)
		if !ok {
			return fmt.Errorf("invalid completionHistory metadata")
		}
		for _, rawRecord := range records {
			record, ok := rawRecord.(map[string]any)
			if !ok {
				return fmt.Errorf("invalid completionHistory metadata")
			}
			_, ok = record["hasTime"].(bool)
			if !ok {
				return fmt.Errorf("invalid completionHistory metadata")
			}
			if value, exists := record["scheduledAt"]; exists && value != nil {
				scheduledAt, ok := value.(string)
				if !ok || !isCanonicalScheduledAt(scheduledAt) {
					return fmt.Errorf("invalid completionHistory metadata")
				}
			} else if !exists {
				return fmt.Errorf("invalid completionHistory metadata")
			}
			completedAt, ok := record["completedAt"].(string)
			if !ok || !isCanonicalCompletedAt(completedAt) {
				return fmt.Errorf("invalid completionHistory metadata")
			}
		}
	}

	return nil
}
