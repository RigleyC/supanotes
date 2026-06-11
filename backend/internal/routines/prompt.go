package routines

import (
	_ "embed"
	"fmt"
)

//go:embed briefs/daily.md
var dailyBriefMD string

//go:embed briefs/weekly.md
var weeklyBriefMD string

func buildBriefPrompt(routineType string, ragContext string) string {
	var prompt string
	switch routineType {
	case "daily":
		prompt = dailyBriefMD
	case "weekly":
		prompt = weeklyBriefMD
	}
	return fmt.Sprintf("%s\n\nContexto Atual:\n%s", prompt, ragContext)
}
