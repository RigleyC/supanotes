package agent

import (
	"context"
	"fmt"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type ResponseBuilder struct {
	client llm.Client
}

func NewResponseBuilder(client llm.Client) *ResponseBuilder {
	return &ResponseBuilder{client: client}
}

func (rb *ResponseBuilder) BuildResponse(ctx context.Context, userQuery string, intent Intent, executionResults string, plannerState string, contextBrief string) (string, error) {
	systemPrompt := `Você é o Apresentador de Respostas do SupaNotes (Response Builder). Sua função é receber o rascunho de execução do agente, o plano original e o contexto, e formatar a resposta final para o usuário de maneira bonita, organizada e profissional, em português (pt-BR).
Adapte a formatação conforme o Intent:
- DailySummary: Apresente um sumário do dia, tarefas de hoje/vencidas organizadas por relevância, insights úteis e sugestões de próximas ações.
- SearchKnowledge: Apresente as informações encontradas de forma estruturada, com títulos claros e marcadores.
- ProjectPlanning: Destaque o progresso do projeto, tarefas pendentes e prazos de forma estruturada.
- TaskManagement: Confirme claramente o status das tarefas alteradas/criadas.
- MemoryQuestion: Responda diretamente ao fato questionado.
- Organization: Apresente o resumo da organização realizada.
- Brainstorming: Apresente as ideias e insights de forma criativa e visualmente atraente.
- GeneralChat: Conversa normal ou saudação amigável.

Não invente ferramentas nem simule novos passos. Apenas formate e apresente o resultado final contido na execução atual.`

	req := llm.Request{
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: fmt.Sprintf("Query: %s\nIntent: %s\nExecution Results:\n%s\nPlanner State:\n%s\nContext:\n%s", userQuery, intent, executionResults, plannerState, contextBrief)},
		},
		MaxTokens:   2000,
		Temperature: 0.3,
	}

	res, err := rb.client.Complete(ctx, req)
	if err != nil {
		return executionResults, err // fallback to raw execution results on error
	}
	return res.Content, nil
}
