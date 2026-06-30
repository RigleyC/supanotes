package agent

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type PlanStep struct {
	ToolName    string `json:"tool_name"`
	Description string `json:"description"`
}

type ExecutionPlan struct {
	Steps []PlanStep `json:"steps"`
}

type Planner struct {
	client llm.Client
}

func NewPlanner(client llm.Client) *Planner {
	return &Planner{client: client}
}

func (p *Planner) GeneratePlan(ctx context.Context, query string, intent Intent, contextBrief string) (*ExecutionPlan, error) {
	systemPrompt := `Voce e um Planejador de Agente de IA. Analise a requisicao do usuario, a intencao detectada e o contexto atual, e elabore um plano de execucao linear composto por ferramentas especificas a executar de forma silenciosa para resolver o objetivo.
Responda APENAS com um objeto JSON valido no formato abaixo, sem tags Markdown:
{
  "steps": [
    { "tool_name": "nome_da_ferramenta", "description": "descricao da acao neste passo" }
  ]
}`
	req := llm.Request{
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: fmt.Sprintf("Query: %s\nIntent: %s\nContext:\n%s", query, intent, contextBrief)},
		},
		MaxTokens:   1000,
		Temperature: 0.0,
	}
	res, err := p.client.Complete(ctx, req)
	if err != nil {
		return nil, err
	}
	var plan ExecutionPlan
	if err := json.Unmarshal([]byte(res.Content), &plan); err != nil {
		return nil, fmt.Errorf("planner: unmarshal json: %w", err)
	}
	return &plan, nil
}
