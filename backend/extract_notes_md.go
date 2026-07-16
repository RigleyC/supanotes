package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strings"
)

func main() {
	file, err := os.Open("backup.sql")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	out, err := os.Create("extracted_notes.md")
	if err != nil {
		log.Fatal(err)
	}
	defer out.Close()

	scanner := bufio.NewScanner(file)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	inNotesBlock := false
	exported := 0

	out.WriteString("# Notas Exportadas do Backup\n\n")

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "COPY public.notes ") {
			inNotesBlock = true
			continue
		}
		if inNotesBlock {
			if line == "\\." {
				break
			}
			parts := strings.Split(line, "\t")
			if len(parts) < 12 {
				continue
			}

			deletedAt := parts[9]
			if deletedAt != "\\N" {
				continue // Skip deleted notes
			}

			content := strings.ReplaceAll(parts[3], "\\n", "\n")
			content = strings.ReplaceAll(content, "\\t", "\t")
			if parts[3] == "\\N" {
				content = ""
			}

			if strings.TrimSpace(content) == "" {
				continue
			}

			out.WriteString(fmt.Sprintf("## Nota %d\n\n%s\n\n---\n\n", exported+1, content))
			exported++
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatal("Scanner error: ", err)
	}
	
	fmt.Printf("Exported %d notes\n", exported)
}
