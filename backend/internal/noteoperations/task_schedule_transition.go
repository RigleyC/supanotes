package noteoperations

import (
	"fmt"
	"reflect"
)

// validateTaskScheduleMetadataTransition protects TaskNode completion history
// while the generic document executor applies partial metadata patches.
func validateTaskScheduleMetadataTransition(
	block Block,
	patch map[string]any,
	evidence []taskCompletionHistoryRecord,
) error {
	if block.Type != string(BlockTask) || patch == nil {
		return nil
	}

	before := block.Metadata
	after := make(map[string]any, len(before)+len(patch))
	for key, value := range before {
		after[key] = value
	}
	for key, value := range patch {
		if value == nil {
			delete(after, key)
		} else {
			after[key] = value
		}
	}

	priorHistory := completionHistoryKeys(before["completionHistory"])
	afterHistory := completionHistoryKeys(after["completionHistory"])
	for key := range priorHistory {
		if !afterHistory[key] {
			return fmt.Errorf("task metadata change must preserve existing completionHistory")
		}
	}
	if len(evidence) == 0 && isLegacyOneOffCompletion(before, after, patch) {
		return nil
	}
	scheduleChanged := !sameTaskSchedule(before, after)
	for _, record := range activeTaskCompletionRecords(before) {
		if activeCompletionIsPreserved(record, after) || afterHistory[completionHistoryKey(record)] {
			continue
		}
		if !scheduleChanged && isReopenedOneOffCompletion(before, after, record) {
			continue
		}
		return fmt.Errorf("task metadata change must preserve removed completions in completionHistory")
	}
	if !scheduleChanged {
		return nil
	}
	if boolMetadata(before, "isCompleted") && stringMetadata(before, "lastCompletedAt") == "" {
		return fmt.Errorf("completed task without lastCompletedAt cannot change schedule without losing completion history")
	}

	for _, record := range append(activeTaskCompletionRecords(before), evidence...) {
		if !afterHistory[completionHistoryKey(record)] {
			return fmt.Errorf("task schedule change must preserve active completions in completionHistory")
		}
	}

	_, hasCompletions := after["completions"]
	if boolMetadata(after, "isCompleted") || stringMetadata(after, "lastCompletedAt") != "" || hasCompletions {
		return fmt.Errorf("task schedule change must clear active completion metadata")
	}
	return nil
}

// Older Flutter clients removed dueDate when completing a nonrecurring task.
// Accept only that exact completion transition; schedule edits still need to
// archive history and clear active completion state.
func isLegacyOneOffCompletion(
	before map[string]any,
	after map[string]any,
	patch map[string]any,
) bool {
	if stringMetadata(before, "recurrenceRule") != "" ||
		stringMetadata(after, "recurrenceRule") != "" ||
		stringMetadata(before, "dueDate") == "" ||
		stringMetadata(after, "dueDate") != "" ||
		boolMetadata(before, "isCompleted") ||
		!boolMetadata(after, "isCompleted") ||
		stringMetadata(before, "lastCompletedAt") != "" ||
		stringMetadata(before, "reminder") != "" ||
		!isCanonicalCompletedAt(stringMetadata(after, "lastCompletedAt")) ||
		boolMetadata(before, "hasTime") != boolMetadata(after, "hasTime") ||
		len(taskCompletions(before)) != 0 ||
		len(activeTaskCompletionRecords(before)) != 0 ||
		!onlyLegacyCompletionFieldsChanged(before, after) {
		return false
	}

	dueDate, hasDueDatePatch := patch["dueDate"]
	isCompleted, hasIsCompletedPatch := patch["isCompleted"]
	lastCompletedAt, hasLastCompletedAtPatch := patch["lastCompletedAt"]
	return hasDueDatePatch && dueDate == nil &&
		hasIsCompletedPatch && isCompleted == true &&
		hasLastCompletedAtPatch && lastCompletedAt == after["lastCompletedAt"]
}

func onlyLegacyCompletionFieldsChanged(before, after map[string]any) bool {
	const (
		dueDateKey         = "dueDate"
		isCompletedKey     = "isCompleted"
		lastCompletedAtKey = "lastCompletedAt"
	)
	filteredBefore := make(map[string]any, len(before))
	filteredAfter := make(map[string]any, len(after))
	for key, value := range before {
		if key == dueDateKey || key == isCompletedKey || key == lastCompletedAtKey {
			continue
		}
		filteredBefore[key] = value
	}
	for key, value := range after {
		if key == dueDateKey || key == isCompletedKey || key == lastCompletedAtKey {
			continue
		}
		filteredAfter[key] = value
	}
	return reflect.DeepEqual(filteredBefore, filteredAfter)
}

func isReopenedOneOffCompletion(
	before map[string]any,
	after map[string]any,
	record taskCompletionHistoryRecord,
) bool {
	return record.isOneOff && boolMetadata(before, "isCompleted") && stringMetadata(before, "recurrenceRule") == "" &&
		!boolMetadata(after, "isCompleted") && stringMetadata(after, "lastCompletedAt") == "" &&
		record.completedAt == stringMetadata(before, "lastCompletedAt")
}

func activeCompletionIsPreserved(record taskCompletionHistoryRecord, metadata map[string]any) bool {
	if record.scheduledAt != nil {
		if completedAt, ok := taskCompletions(metadata)[*record.scheduledAt].(string); ok &&
			completedAt == record.completedAt && boolMetadata(metadata, "hasTime") == record.hasTime {
			return true
		}
	}
	if boolMetadata(metadata, "isCompleted") &&
		stringMetadata(metadata, "lastCompletedAt") == record.completedAt &&
		boolMetadata(metadata, "hasTime") == record.hasTime {
		dueDate := stringMetadata(metadata, "dueDate")
		if (record.scheduledAt == nil && dueDate == "") || (record.scheduledAt != nil && dueDate == *record.scheduledAt) {
			return true
		}
	}
	return false
}

func sameTaskSchedule(left, right map[string]any) bool {
	if stringMetadata(left, "dueDate") != stringMetadata(right, "dueDate") ||
		stringMetadata(left, "recurrenceRule") != stringMetadata(right, "recurrenceRule") {
		return false
	}
	return boolMetadata(left, "hasTime") == boolMetadata(right, "hasTime")
}

func stringMetadata(metadata map[string]any, key string) string {
	value, _ := metadata[key].(string)
	return value
}

func boolMetadata(metadata map[string]any, key string) bool {
	value, _ := metadata[key].(bool)
	return value
}

type taskCompletionHistoryRecord struct {
	scheduledAt *string
	hasTime     bool
	completedAt string
	isOneOff    bool
}

func activeTaskCompletionRecords(metadata map[string]any) []taskCompletionHistoryRecord {
	var records []taskCompletionHistoryRecord
	for scheduledAt, rawCompletedAt := range taskCompletions(metadata) {
		completedAt, ok := rawCompletedAt.(string)
		if !ok {
			continue
		}
		scheduled := scheduledAt
		records = append(records, taskCompletionHistoryRecord{
			scheduledAt: &scheduled,
			hasTime:     boolMetadata(metadata, "hasTime"),
			completedAt: completedAt,
		})
	}

	if boolMetadata(metadata, "isCompleted") {
		completedAt := stringMetadata(metadata, "lastCompletedAt")
		if completedAt != "" {
			var scheduledAt *string
			if dueDate := stringMetadata(metadata, "dueDate"); dueDate != "" {
				scheduledAt = &dueDate
			}
			records = append(records, taskCompletionHistoryRecord{
				scheduledAt: scheduledAt,
				hasTime:     boolMetadata(metadata, "hasTime"),
				completedAt: completedAt,
				isOneOff:    true,
			})
		}
	}
	return records
}

func taskCompletions(metadata map[string]any) map[string]any {
	completions, _ := metadata["completions"].(map[string]any)
	return completions
}

func completionHistoryKeys(raw any) map[string]bool {
	keys := make(map[string]bool)
	records, ok := raw.([]any)
	if !ok {
		return keys
	}
	for _, rawRecord := range records {
		record, ok := rawRecord.(map[string]any)
		if !ok {
			continue
		}
		var scheduledAt *string
		if value, exists := record["scheduledAt"]; exists && value != nil {
			if scheduled, ok := value.(string); ok {
				scheduledAt = &scheduled
			}
		}
		hasTime, _ := record["hasTime"].(bool)
		completedAt, _ := record["completedAt"].(string)
		keys[completionHistoryKey(taskCompletionHistoryRecord{
			scheduledAt: scheduledAt,
			hasTime:     hasTime,
			completedAt: completedAt,
		})] = true
	}
	return keys
}

func completionHistoryKey(record taskCompletionHistoryRecord) string {
	scheduledAt := "null"
	if record.scheduledAt != nil {
		scheduledAt = *record.scheduledAt
	}
	return fmt.Sprintf("%s|%t|%s", scheduledAt, record.hasTime, record.completedAt)
}
