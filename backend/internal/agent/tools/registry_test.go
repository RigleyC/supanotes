package tools

import "testing"

func TestToolRegistryRiskDefaults(t *testing.T) {
	registry := &ToolRegistry{tools: map[string]ToolExecutor{}}

	cases := map[string]ToolRisk{
		"search_notes": ToolRiskRead,
		"get_note":     ToolRiskRead,
		"add_note":     ToolRiskLowWrite,
		"update_soul":  ToolRiskLowWrite,
		"update_note":  ToolRiskSensitiveWrite,
		"delete_memory": ToolRiskSensitiveWrite,
	}

	for name, want := range cases {
		if got := registry.Risk(name); got != want {
			t.Fatalf("%s risk: want %s, got %s", name, want, got)
		}
	}
}
