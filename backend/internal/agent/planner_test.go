package agent

import (
	"context"
	"testing"
)

func TestPlannerGeneratePlan(t *testing.T) {
	tests := []struct {
		name      string
		content   string
		useErrStub bool
		want      *ExecutionPlan
		wantErr   bool
	}{
		{
			name:    "valid_plan",
			content: `{"steps": [{"tool_name": "search_notes", "description": "Buscar notas sobre organizacao"}, {"tool_name": "suggest_action", "description": "Sugerir acao para cada nota"}]}`,
			want: &ExecutionPlan{
				Steps: []PlanStep{
					{ToolName: "search_notes", Description: "Buscar notas sobre organizacao"},
					{ToolName: "suggest_action", Description: "Sugerir acao para cada nota"},
				},
			},
			wantErr: false,
		},
		{
			name:       "llm_error",
			useErrStub: true,
			wantErr:    true,
		},
		{
			name:    "invalid_json",
			content: `not json`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var planner *Planner
			if tt.useErrStub {
				planner = NewPlanner(&errorStubLLMClient{})
			} else {
				planner = NewPlanner(&stubLLMClient{content: tt.content})
			}
			plan, err := planner.GeneratePlan(context.Background(), "Organizar meu inbox", IntentOrganization, "")
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("GeneratePlan failed: %v", err)
			}
			if len(plan.Steps) != len(tt.want.Steps) {
				t.Fatalf("expected %d steps, got %d", len(tt.want.Steps), len(plan.Steps))
			}
			for i, step := range plan.Steps {
				if step.ToolName != tt.want.Steps[i].ToolName {
					t.Errorf("step %d: expected tool_name %q, got %q", i, tt.want.Steps[i].ToolName, step.ToolName)
				}
				if step.Description != tt.want.Steps[i].Description {
					t.Errorf("step %d: expected description %q, got %q", i, tt.want.Steps[i].Description, step.Description)
				}
			}
		})
	}
}
