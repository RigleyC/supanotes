package sync

import (
	"encoding/json"
	"strings"

	"github.com/reearth/ygo/crdt"
)

func deriveMarkdownFromDoc(doc *crdt.Doc) string {
	entries := nodesFromDoc(doc)
	if len(entries) == 0 {
		return ""
	}
	var lines []string
	for _, nd := range entries {
		switch nd.Type {
		case "header":
			level := 1
			var data struct {
				Level int `json:"level"`
			}
			if nd.Data != nil {
				json.Unmarshal(nd.Data, &data)
				level = data.Level
				if level < 1 {
					level = 1
				}
			}
			prefix := strings.Repeat("#", level)
			lines = append(lines, prefix+" "+nd.Text)
		case "task":
			completed, _ := nd.Metadata["completed"].(bool)
			checkbox := " "
			if completed {
				checkbox = "x"
			}
			lines = append(lines, "- ["+checkbox+"] "+nd.Text)
		case "list_item":
			lines = append(lines, "- "+nd.Text)
		case "divider":
			lines = append(lines, "---")
		case "image":
			lines = append(lines, "[image]")
		default:
			lines = append(lines, nd.Text)
		}
	}
	return strings.Join(lines, "\n")
}
