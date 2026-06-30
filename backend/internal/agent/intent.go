package agent

import (
	"context"
	"log/slog"
	"strings"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type Intent string

const (
	IntentDailySummary    Intent = "DailySummary"
	IntentSearchKnowledge Intent = "SearchKnowledge"
	IntentProjectPlanning Intent = "ProjectPlanning"
	IntentTaskManagement  Intent = "TaskManagement"
	IntentMemoryQuestion  Intent = "MemoryQuestion"
	IntentOrganization    Intent = "Organization"
	IntentBrainstorming   Intent = "Brainstorming"
	IntentGeneralChat     Intent = "GeneralChat"
)

type IntentClassifier struct {
	client llm.Client
}

func NewIntentClassifier(client llm.Client) *IntentClassifier {
	return &IntentClassifier{client: client}
}

var intentClassifierPrompt = `Você é um Classificador de Intenção especializado. Analise a mensagem do usuário e responda APENAS com um dos seguintes nomes de intenção, sem explicações, pontuação ou formatação adicional:
- DailySummary: Perguntas sobre o dia, agenda, o que fazer hoje, tarefas vencidas ou resumo diário.
- SearchKnowledge: Buscas semânticas sobre anotações, notas antigas ou informações gerais.
- ProjectPlanning: Planejamento de projetos, notas vinculadas, metas e tarefas de projeto.
- TaskManagement: Criação, atualização ou conclusão de tarefas.
- MemoryQuestion: Perguntas sobre fatos que o agente deveria se lembrar/memorizar.
- Organization: Organização de notas, inbox, arquivar ou limpar notas.
- Brainstorming: Sessões criativas, ideias, pensamentos.
- GeneralChat: Conversa fiada, saudações ou mensagens gerais.`

func (ic *IntentClassifier) Classify(ctx context.Context, message string) (Intent, error) {
	req := llm.Request{
		System: intentClassifierPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: message},
		},
		MaxTokens:   50,
		Temperature: 0.0,
	}
	res, err := ic.client.Complete(ctx, req)
	if err != nil {
		return IntentGeneralChat, err
	}
	cleanIntent := Intent(strings.TrimSpace(res.Content))
	switch cleanIntent {
	case IntentDailySummary, IntentSearchKnowledge, IntentProjectPlanning, IntentTaskManagement, IntentMemoryQuestion, IntentOrganization, IntentBrainstorming, IntentGeneralChat:
		return cleanIntent, nil
	default:
		slog.Warn("unrecognized intent from LLM, falling back to GeneralChat",
			"raw_intent", string(cleanIntent))
		return IntentGeneralChat, nil
	}
}
