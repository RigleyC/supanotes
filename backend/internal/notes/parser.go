package notes

import (
	"encoding/json"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

var (
	markdownHeaderRegex  = regexp.MustCompile(`^(#{1,6})\s+(.*)$`)
	markdownTaskRegex    = regexp.MustCompile(`^-\s+\[([ xX])\]\s+(.*)$`)
	markdownDividerRegex = regexp.MustCompile(`^(?:---|___|\*\*\*)\s*$`)
)

type ParsedNode struct {
	ID       pgtype.UUID
	Type     string
	Data     []byte
	Text     string
	IsTask   bool
	Complete bool
}

func ParseMarkdownToNodes(content string) []ParsedNode {
	lines := strings.Split(content, "\n")
	var result []ParsedNode

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		var nodeType string
		var dataMap map[string]interface{}
		var textVal string
		isTask := false
		complete := false

		if matches := markdownHeaderRegex.FindStringSubmatch(trimmed); len(matches) == 3 {
			nodeType = "header"
			level := len(matches[1])
			textVal = matches[2]
			dataMap = map[string]interface{}{
				"text":  textVal,
				"level": level,
			}
		} else if matches := markdownTaskRegex.FindStringSubmatch(trimmed); len(matches) == 3 {
			nodeType = "task"
			isTask = true
			complete = strings.ToLower(matches[1]) == "x"
			textVal = matches[2]
			dataMap = map[string]interface{}{
				"text":       textVal,
				"isComplete": complete,
			}
		} else if markdownDividerRegex.MatchString(trimmed) {
			nodeType = "divider"
			dataMap = map[string]interface{}{}
		} else {
			nodeType = "paragraph"
			textVal = trimmed
			dataMap = map[string]interface{}{
				"text": textVal,
			}
		}

		dataBytes, _ := json.Marshal(dataMap)
		newUUID := uuid.New()

		result = append(result, ParsedNode{
			ID:       pgtype.UUID{Bytes: newUUID, Valid: true},
			Type:     nodeType,
			Data:     dataBytes,
			Text:     textVal,
			IsTask:   isTask,
			Complete: complete,
		})
	}

	return result
}
