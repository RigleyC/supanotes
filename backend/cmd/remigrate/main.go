package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	taskCommentRe     = regexp.MustCompile(`<!--\s*task:([0-9a-f\-]+)\s*-->`)
	dividerRe         = regexp.MustCompile(`---\s*<!--\s*divider:([0-9a-f\-]+)(?:\|index:\d+)?\s*-->`)
	checkboxUnchecked = regexp.MustCompile(`- \[ \] (.*)`)
	checkboxChecked   = regexp.MustCompile(`- \[x\] (.*)`)
	boldRe            = regexp.MustCompile(`\*\*(.+?)\*\*`)
	italicRe          = regexp.MustCompile(`\*(.+?)\*`)
	strikeRe          = regexp.MustCompile(`~~(.+?)~~`)
)

type Span struct {
	Attribution string `json:"attribution"`
	Start       int    `json:"start"`
	End         int    `json:"end"`
}

func parseInlineFormatting(text string) (string, []Span) {
	spans := []Span{}
	for {
		loc := boldRe.FindStringIndex(text)
		if loc == nil { break }
		match := boldRe.FindStringSubmatch(text)
		inner := match[1]
		start := loc[0]
		text = text[:loc[0]] + inner + text[loc[1]:]
		spans = append(spans, Span{Attribution: "bold", Start: start, End: start + len(inner) - 1})
	}
	for {
		loc := italicRe.FindStringIndex(text)
		if loc == nil { break }
		match := italicRe.FindStringSubmatch(text)
		inner := match[1]
		start := loc[0]
		text = text[:loc[0]] + inner + text[loc[1]:]
		spans = append(spans, Span{Attribution: "italics", Start: start, End: start + len(inner) - 1})
	}
	for {
		loc := strikeRe.FindStringIndex(text)
		if loc == nil { break }
		match := strikeRe.FindStringSubmatch(text)
		inner := match[1]
		start := loc[0]
		text = text[:loc[0]] + inner + text[loc[1]:]
		spans = append(spans, Span{Attribution: "strikethrough", Start: start, End: start + len(inner) - 1})
	}
	return text, spans
}

type NodeOut struct {
	ID       string
	Type     string
	Data     map[string]interface{}
}

func parseLine(line string, isFirst bool) *NodeOut {
	// Calculate indent based on leading spaces (2 spaces = 1 indent level)
	leadingSpaces := 0
	for _, ch := range line {
		if ch == ' ' {
			leadingSpaces++
		} else if ch == '\t' {
			leadingSpaces += 4
		} else {
			break
		}
	}
	indent := leadingSpaces / 2
	trimmedLine := strings.TrimSpace(line)

	if m := dividerRe.FindStringSubmatch(trimmedLine); m != nil {
		return &NodeOut{ID: m[1], Type: "divider", Data: map[string]interface{}{}}
	}
	if m := checkboxUnchecked.FindStringSubmatch(trimmedLine); m != nil {
		id := uuid.New().String()
		if tm := taskCommentRe.FindStringSubmatch(m[1]); tm != nil {
			id = tm[1]
		}
		clean := strings.TrimSpace(taskCommentRe.ReplaceAllString(m[1], ""))
		pt, sp := parseInlineFormatting(clean)
		return &NodeOut{ID: id, Type: "task", Data: map[string]interface{}{"text": pt, "spans": sp, "completed": false, "indent": indent}}
	}
	if m := checkboxChecked.FindStringSubmatch(trimmedLine); m != nil {
		id := uuid.New().String()
		if tm := taskCommentRe.FindStringSubmatch(m[1]); tm != nil {
			id = tm[1]
		}
		clean := strings.TrimSpace(taskCommentRe.ReplaceAllString(m[1], ""))
		pt, sp := parseInlineFormatting(clean)
		return &NodeOut{ID: id, Type: "task", Data: map[string]interface{}{"text": pt, "spans": sp, "completed": true, "indent": indent}}
	}
	if tm := taskCommentRe.FindStringSubmatch(trimmedLine); tm != nil {
		clean := strings.TrimSpace(taskCommentRe.ReplaceAllString(trimmedLine, ""))
		clean = strings.TrimPrefix(clean, "- [ ] ")
		clean = strings.TrimPrefix(clean, "- [x] ")
		pt, sp := parseInlineFormatting(clean)
		return &NodeOut{ID: tm[1], Type: "task", Data: map[string]interface{}{"text": pt, "spans": sp, "completed": false, "indent": indent}}
	}
	if trimmedLine == "---" || trimmedLine == "***" || strings.HasPrefix(trimmedLine, "————") {
		return &NodeOut{ID: uuid.New().String(), Type: "divider", Data: map[string]interface{}{}}
	}
	
	if isFirst && !strings.HasPrefix(trimmedLine, "#") {
		// First line is always a header level 1 if it wasn't caught by something else
		pt, sp := parseInlineFormatting(trimmedLine)
		return &NodeOut{ID: uuid.New().String(), Type: "header", Data: map[string]interface{}{"text": pt, "spans": sp, "level": 1}}
	}

	if strings.HasPrefix(trimmedLine, "#") {
		level := 0
		for i := 0; i < len(trimmedLine) && trimmedLine[i] == '#'; i++ { level++ }
		if level <= 6 && len(trimmedLine) > level && trimmedLine[level] == ' ' {
			pt, sp := parseInlineFormatting(trimmedLine[level+1:])
			return &NodeOut{ID: uuid.New().String(), Type: "header", Data: map[string]interface{}{"text": pt, "spans": sp, "level": level}}
		}
	}
	if strings.HasPrefix(trimmedLine, "> ") {
		pt, sp := parseInlineFormatting(trimmedLine[2:])
		return &NodeOut{ID: uuid.New().String(), Type: "blockquote", Data: map[string]interface{}{"text": pt, "spans": sp}}
	}
	if (strings.HasPrefix(trimmedLine, "* ") || strings.HasPrefix(trimmedLine, "- ")) && !strings.HasPrefix(trimmedLine, "- [ ]") && !strings.HasPrefix(trimmedLine, "- [x]") {
		pt, sp := parseInlineFormatting(trimmedLine[2:])
		return &NodeOut{ID: uuid.New().String(), Type: "list_item", Data: map[string]interface{}{"text": pt, "spans": sp, "type": "unordered", "indent": indent}}
	}
	orderedRe := regexp.MustCompile(`^(\d+)\.\s(.*)$`)
	if m := orderedRe.FindStringSubmatch(trimmedLine); m != nil {
		pt, sp := parseInlineFormatting(m[2])
		return &NodeOut{ID: uuid.New().String(), Type: "list_item", Data: map[string]interface{}{"text": pt, "spans": sp, "type": "ordered", "indent": indent}}
	}
	pt, sp := parseInlineFormatting(trimmedLine)
	return &NodeOut{ID: uuid.New().String(), Type: "paragraph", Data: map[string]interface{}{"text": pt, "spans": sp}}
}

func main() {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		connStr = "postgres://backend_winter_waterfall_5807:BpXimItNqgwcS1i@localhost:5433/backend_winter_waterfall_5807?sslmode=disable"
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, connStr)
	if err != nil { log.Fatalf("Unable to connect: %v", err) }
	defer pool.Close()

	rows, err := pool.Query(ctx, "SELECT id, content, user_id FROM notes WHERE content != '' AND deleted_at IS NULL")
	if err != nil { log.Fatalf("Failed to query notes: %v", err) }
	defer rows.Close()

	type Note struct { ID, Content, UserID string }
	var notes []Note
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.Content, &n.UserID); err != nil { log.Fatal(err) }
		notes = append(notes, n)
	}
	rows.Close()

	fmt.Printf("Found %d notes to migrate\n", len(notes))

	_, err = pool.Exec(ctx, "DELETE FROM note_nodes")
	if err != nil { log.Fatalf("Failed to clear note_nodes: %v", err) }
	fmt.Println("Cleared note_nodes table")

	inserted := 0
	for _, note := range notes {
		lines := strings.Split(note.Content, "\n")
		position := 0
		for _, line := range lines {
			if strings.TrimSpace(line) == "" { continue }
			
			isFirst := position == 0
			nodeOut := parseLine(line, isFirst)
			if nodeOut == nil { continue }
			if nodeOut.Data["spans"] == nil { nodeOut.Data["spans"] = []Span{} }
			dataBytes, _ := json.Marshal(nodeOut.Data)
			now := time.Now()
			_, err := pool.Exec(ctx, `INSERT INTO note_nodes (id, note_id, type, data, position, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
				nodeOut.ID, note.ID, nodeOut.Type, string(dataBytes), position, now, now)
			if err != nil {
				log.Printf("Failed to insert node for note %s: %v", note.ID, err)
			} else {
				inserted++
			}
			position++
		}
	}
	fmt.Printf("Migration complete. Inserted %d nodes.\n", inserted)
}
