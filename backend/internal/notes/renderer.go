package notes

import (
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func RenderNoteToMarkdown(nodes []sqlcgen.NoteNode, tasks map[pgtype.UUID]sqlcgen.Task) string {
	var sb strings.Builder
	for _, n := range nodes {
		var data map[string]interface{}
		json.Unmarshal(n.Data, &data)
		text, _ := data["text"].(string)

		switch n.Type {
		case "paragraph":
			sb.WriteString(text + "\n")
		case "task":
			status := " "
			if t, ok := tasks[n.ID]; ok && t.Status == "done" {
				status = "x"
			}
			sb.WriteString("- [" + status + "] " + text + "\n")
		}
	}
	return sb.String()
}
