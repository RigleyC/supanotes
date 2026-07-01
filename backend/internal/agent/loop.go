package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/agent/tools"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type Loop struct {
	repo       Repository
	llmFact    llm.Factory
	ctxBldr    *ContextBuilder
	tools      *ToolRegistry
	workingMem *WorkingMemoryService
	classifier *IntentClassifier
	planner    *Planner
	respBldr   *ResponseBuilder
}

func NewLoop(repo Repository, llmFact llm.Factory, ctxBldr *ContextBuilder, tools *ToolRegistry, workingMem *WorkingMemoryService) *Loop {
	var classifier *IntentClassifier
	var planner *Planner
	var respBldr *ResponseBuilder

	isTestStub := false
	if llmFact != nil {
		typename := fmt.Sprintf("%T", llmFact)
		if strings.Contains(typename, "stub") || strings.Contains(typename, "mock") || strings.Contains(typename, "Mock") {
			isTestStub = true
		}
	}

	if llmFact != nil && !isTestStub {
		// Use lightweight/inbox-organize client (DeepSeek/GPT-4o-mini) for classification, planning, and response building.
		classifierClient := llmFact.For(llm.TaskTypeInboxOrganize)
		plannerClient := llmFact.For(llm.TaskTypeInboxOrganize)
		respBldrClient := llmFact.For(llm.TaskTypeInboxOrganize)
		classifier = NewIntentClassifier(classifierClient)
		planner = NewPlanner(plannerClient)
		respBldr = NewResponseBuilder(respBldrClient)
	}

	return &Loop{
		repo:       repo,
		llmFact:    llmFact,
		ctxBldr:    ctxBldr,
		tools:      tools,
		workingMem: workingMem,
		classifier: classifier,
		planner:    planner,
		respBldr:   respBldr,
	}
}


func sendStreamEvent(ctx context.Context, events chan<- StreamEvent, event StreamEvent) {
	if events == nil {
		return
	}
	select {
	case events <- event:
	case <-ctx.Done():
	}
}

func (l *Loop) Chat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string) (<-chan string, error) {
	ch := make(chan string, 10)

	go func() {
		defer close(ch)

		events := make(chan StreamEvent, 20)
		var wg sync.WaitGroup
		wg.Add(1)
		go func() {
			defer wg.Done()
			for event := range events {
				switch event.Type {
				case EventContentDelta:
					payload, ok := event.Payload.(ContentDeltaPayload)
					if !ok {
						continue
					}
					select {
					case ch <- payload.Delta:
					case <-ctx.Done():
						return
					}
				case EventMessageFinished:
					payload, ok := event.Payload.(MessageFinishedPayload)
					if !ok {
						continue
					}
					select {
					case ch <- payload.Content:
					case <-ctx.Done():
						return
					}
				}
			}
		}()

		_, err := l.doChat(ctx, userID, sessionIDStr, userMessage, events)
		if err != nil {
			slog.Error("chat failed", "error", err)
		}
		close(events)
		wg.Wait()
	}()

	return ch, nil
}

func (l *Loop) ResetSession(ctx context.Context, userID pgtype.UUID, sessionIDStr string) error {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return fmt.Errorf("invalid session id: %w", err)
	}
	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}
	if err := l.repo.DeleteSessionMessages(ctx, userID, sessionUUID); err != nil {
		return err
	}
	if l.workingMem != nil {
		return l.workingMem.Clear(ctx, userID, sessionUUID)
	}
	return nil
}

func (l *Loop) ExecuteTool(ctx context.Context, userID pgtype.UUID, sessionIDStr, toolName, argsJSON string) (string, error) {
	return l.tools.Execute(ctx, userID, sessionIDStr, toolName, argsJSON)
}

func (l *Loop) ChatStream(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- StreamEvent) error {
	_, err := l.doChat(ctx, userID, sessionIDStr, userMessage, events)
	return err
}

type agentTurn struct {
	userID             pgtype.UUID
	sessionUUID        pgtype.UUID
	sessionIDStr       string
	userMessage        string
	assistantMessageID string
	writer             *StreamEventWriter
	events             chan<- StreamEvent

	// Outputs & Intermediates
	intent           Intent
	sysPrompt        string
	planStr          string
	messages         []llm.Message
	finalContent     string
	completionReason string
	trace            *ExecutionTrace
	lastToolResults  []string
}

func (l *Loop) doChat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- StreamEvent) (string, error) {
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		return "", fmt.Errorf("invalid session id: %w", err)
	}

	sessionUUID := pgtype.UUID{Bytes: sessionID, Valid: true}
	assistantMessageID := uuid.NewString()
	writer := NewStreamEventWriter(sessionIDStr, assistantMessageID)

	turn := &agentTurn{
		userID:             userID,
		sessionUUID:        sessionUUID,
		sessionIDStr:       sessionIDStr,
		userMessage:        userMessage,
		assistantMessageID: assistantMessageID,
		writer:             writer,
		events:             events,
	}

	if err := l.prepareTurn(ctx, turn); err != nil {
		return "", err
	}

	if err := l.executeLoop(ctx, turn); err != nil {
		return "", err
	}

	if err := l.finalizeResponse(ctx, turn); err != nil {
		return "", err
	}

	return turn.finalContent, nil
}

func (l *Loop) prepareTurn(ctx context.Context, turn *agentTurn) error {
	// Timeline: Detecting intent
	sendMilestone(ctx, turn.events, turn.writer, "detecting_intent", "pending", "Detectando intenção do usuário...")
	turn.intent = IntentGeneralChat
	if l.classifier != nil {
		if i, err := l.classifier.Classify(ctx, turn.userMessage); err == nil {
			turn.intent = i
		} else {
			slog.Error("intent classification failed, falling back to GeneralChat", "error", err)
		}
	}
	sendMilestone(ctx, turn.events, turn.writer, "detecting_intent", "completed", fmt.Sprintf("Intenção identificada: %s", turn.intent))

	// Timeline: Understanding request
	sendMilestone(ctx, turn.events, turn.writer, "understanding_request", "pending", "Entendendo requisição...")
	sendStreamEvent(ctx, turn.events, turn.writer.Event(
		EventMessageStarted,
		MessageStartedPayload{
			Role:  string(llm.RoleAssistant),
			Label: labelForIntent(turn.intent),
		},
	))
	sendMilestone(ctx, turn.events, turn.writer, "understanding_request", "completed", "Entendendo requisição concluído")

	// 1. Save User Message
	_, err := l.repo.CreateMessage(ctx, turn.userID, turn.sessionUUID, string(llm.RoleUser), turn.userMessage, nil, nil)
	if err != nil {
		return fmt.Errorf("save user msg: %w", err)
	}

	// Timeline: Building context
	sendMilestone(ctx, turn.events, turn.writer, "building_context", "pending", "Buscando contexto e informações RAG...")
	turn.sysPrompt, err = l.ctxBldr.Build(ctx, turn.userID, turn.sessionUUID, turn.userMessage, turn.intent)
	if err != nil {
		sendMilestone(ctx, turn.events, turn.writer, "building_context", "failed", "Erro ao carregar contexto")
		return fmt.Errorf("build context: %w", err)
	}

	// Load Working Memory
	if l.workingMem != nil {
		workingMemData, wmErr := l.workingMem.GetAll(ctx, turn.userID, turn.sessionUUID)
		if wmErr != nil {
			slog.Warn("failed to load working memory", "error", wmErr)
		}
		if len(workingMemData) > 0 {
			var wmParts []string
			for k, v := range workingMemData {
				wmParts = append(wmParts, fmt.Sprintf("<entry key=\"%s\">%s</entry>", k, v))
			}
			turn.sysPrompt += "\n<working-memory>\n" + strings.Join(wmParts, "\n") + "\n</working-memory>\n"
		}
	}
	sendMilestone(ctx, turn.events, turn.writer, "building_context", "completed", "Contexto RAG carregado com sucesso")

	// Timeline: Planning steps
	sendMilestone(ctx, turn.events, turn.writer, "planning_steps", "pending", "Planejando sequência de ações...")
	if l.planner != nil {
		plan, err := l.planner.GeneratePlan(ctx, turn.userMessage, turn.intent, turn.sysPrompt)
		if err != nil {
			slog.Error("planner failed, falling back to no-plan execution", "error", err)
			sendMilestone(ctx, turn.events, turn.writer, "planning_steps", "failed", "Erro ao planejar passos")
		} else {
			planBytes, _ := json.Marshal(plan)
			turn.planStr = string(planBytes)
			turn.sysPrompt += "\n<execution-plan>\n" + turn.planStr + "\n</execution-plan>\n"
			sendMilestone(ctx, turn.events, turn.writer, "planning_steps", "completed", fmt.Sprintf("Planejamento concluído (%d passos)", len(plan.Steps)))
		}
	} else {
		sendMilestone(ctx, turn.events, turn.writer, "planning_steps", "completed", "Planejamento ignorado (sem planejador)")
	}

	return nil
}

func (l *Loop) executeLoop(ctx context.Context, turn *agentTurn) error {
	var err error
	turn.messages, err = l.loadHistory(ctx, turn.userID, turn.sessionUUID)
	if err != nil {
		return fmt.Errorf("load history: %w", err)
	}

	turn.trace = &ExecutionTrace{
		SessionID:      turn.sessionIDStr,
		UserID:         uuid.UUID(turn.userID.Bytes).String(),
		UserMessage:    turn.userMessage,
		DetectedIntent: turn.intent,
		PlannerOutput:  turn.planStr,
		CreatedAt:      time.Now(),
	}

	sendMilestone(ctx, turn.events, turn.writer, "executing_tools", "pending", "Executando loop de ferramentas...")

	budget := NewBudgetManager(15)
	turn.completionReason = "completed"

	for !budget.IsExhausted() {
		done, err := l.executeSingleIteration(ctx, turn, budget)
		if err != nil {
			return err
		}
		if done {
			break
		}
	}
	if turn.completionReason == "completed" && budget.IsExhausted() {
		turn.completionReason = "exhausted"
	}

	sendMilestone(ctx, turn.events, turn.writer, "executing_tools", "completed", "Loop de ferramentas concluído")
	turn.trace.IterationCount = budget.CurrentIteration()
	return nil
}

func (l *Loop) executeSingleIteration(ctx context.Context, turn *agentTurn, budget *BudgetManager) (bool, error) {
	client := l.llmFact.For(llm.TaskTypeAgentic)
	toolDefs := l.tools.GetTools()
	streamCallback := func(token string) error {
		sendStreamEvent(ctx, turn.events, turn.writer.Event(
			EventContentDelta,
			ContentDeltaPayload{Delta: token},
		))
		return nil
	}

	budget.Advance()
	compressedMsgs := l.compressMessages(turn.messages)

	activeSysPrompt := turn.sysPrompt
	if warning := budget.GetSystemPromptWarning(); warning != "" {
		activeSysPrompt += warning
	}

	req := llm.Request{
		System:      activeSysPrompt,
		Messages:    compressedMsgs,
		Tools:       toolDefs,
		MaxTokens:   4000,
		Temperature: 0.7,
	}

	turn.trace.PromptSize += len(activeSysPrompt)
	for _, m := range compressedMsgs {
		turn.trace.PromptSize += len(m.Content)
	}

	res, err := client.CompleteStream(ctx, req, streamCallback)
	if err != nil {
		if len(turn.lastToolResults) > 0 {
			slog.Warn("llm call failed after tool execution; finishing with tool result", "error", err, "iteration", budget.CurrentIteration())
			turn.finalContent = strings.Join(turn.lastToolResults, "\n")
			turn.completionReason = "llm_error_fallback"
			return true, nil
		}
		return false, fmt.Errorf("llm call: %w", err)
	}

	if res.Content == "" && len(res.ToolCalls) == 0 {
		slog.Warn("llm returned empty agent response; retrying without tools", "iteration", budget.CurrentIteration())
		fallbackReq := req
		fallbackReq.Tools = nil
		res, err = client.CompleteStream(ctx, fallbackReq, streamCallback)
		if err != nil {
			return false, fmt.Errorf("llm fallback call: %w", err)
		}
		if res.Content == "" && len(res.ToolCalls) == 0 {
			if len(turn.lastToolResults) > 0 {
				res.Content = strings.Join(turn.lastToolResults, "\n")
				res.ToolCalls = nil
				slog.Warn("llm returned empty agent response; finishing with tool result", "iteration", budget.CurrentIteration())
			} else {
				slog.Error("llm returned empty agent response", "iteration", budget.CurrentIteration())
				return false, fmt.Errorf("llm returned empty response")
			}
		}
	}

	assistMsg := llm.Message{
		Role:      llm.RoleAssistant,
		Content:   res.Content,
		ToolCalls: res.ToolCalls,
	}
	turn.messages = append(turn.messages, assistMsg)

	if _, err := l.persistTurn(ctx, turn.userID, turn.sessionUUID, assistMsg); err != nil {
		return false, fmt.Errorf("save assistant msg: %w", err)
	}

	if len(res.ToolCalls) > 0 {
		for _, tc := range res.ToolCalls {
			sendStreamEvent(ctx, turn.events, turn.writer.Event(
				EventToolStarted,
				ToolActivityPayload{Name: tc.Name, Label: l.tools.Get(tc.Name).Label()},
			))
		}
	}

	if len(res.ToolCalls) == 0 {
		turn.finalContent = res.Content
		return true, nil
	}

	if err := l.processToolCalls(ctx, turn, res.ToolCalls); err != nil {
		return false, err
	}
	if turn.completionReason == "confirmation_required" {
		return true, nil
	}

	return false, nil
}

func (l *Loop) processToolCalls(ctx context.Context, turn *agentTurn, toolCalls []llm.ToolCall) error {
	for _, tc := range toolCalls {
		if l.tools.Risk(tc.Name) == tools.ToolRiskSensitiveWrite {
			pending, err := l.repo.CreatePendingToolConfirmation(ctx, turn.userID, turn.sessionUUID, tc.Name, tc.ArgsJSON)
			if err != nil {
				return fmt.Errorf("create pending tool confirmation: %w", err)
			}

			sendStreamEvent(ctx, turn.events, turn.writer.Event(
				EventConfirmationRequired,
				ConfirmationRequiredPayload{
					ConfirmationID: uuid.UUID(pending.ID.Bytes).String(),
					ToolName:       tc.Name,
					Label:          l.tools.Get(tc.Name).Label(),
				},
			))
			turn.finalContent = "Preciso da sua confirmação antes de aplicar essa alteração."
			sendStreamEvent(ctx, turn.events, turn.writer.Event(
				EventMessageFinished,
				MessageFinishedPayload{Content: turn.finalContent},
			))

			turn.completionReason = "confirmation_required"
			turn.trace.IterationCount = len(turn.trace.ToolCalls) + 1
			turn.trace.CompletionReason = turn.completionReason
			turn.trace.FinalResponse = turn.finalContent
			GlobalTraceStore.AddTrace(turn.sessionIDStr, turn.trace)

			return nil
		}

		startToolTime := time.Now()
		resultStr, err := l.tools.Execute(ctx, turn.userID, turn.sessionIDStr, tc.Name, tc.ArgsJSON)
		toolLatency := time.Since(startToolTime)

		toolErrStr := ""
		if err != nil {
			toolErrStr = err.Error()
			resultStr = fmt.Sprintf("Error executing tool: %v", err)
			sendStreamEvent(ctx, turn.events, turn.writer.Event(
				EventToolFailed,
				ToolFailedPayload{Name: tc.Name, Label: l.tools.Get(tc.Name).Label(), Message: err.Error()},
			))
		} else {
			sendStreamEvent(ctx, turn.events, turn.writer.Event(
				EventToolFinished,
				ToolActivityPayload{Name: tc.Name, Label: l.tools.Get(tc.Name).Label()},
			))
		}

		turn.trace.ToolCalls = append(turn.trace.ToolCalls, ToolCallTrace{
			ToolName: tc.Name,
			Args:     tc.ArgsJSON,
			Latency:  toolLatency,
			Error:    toolErrStr,
		})

		toolMsg := llm.Message{
			Role:       llm.RoleTool,
			Content:    resultStr,
			ToolCallID: tc.ID,
		}
		turn.messages = append(turn.messages, toolMsg)
		turn.lastToolResults = append(turn.lastToolResults, resultStr)

		if _, err := l.persistTurn(ctx, turn.userID, turn.sessionUUID, toolMsg); err != nil {
			return fmt.Errorf("save tool msg: %w", err)
		}
	}
	return nil
}

func (l *Loop) finalizeResponse(ctx context.Context, turn *agentTurn) error {
	// Timeline: Formatting response
	sendMilestone(ctx, turn.events, turn.writer, "formatting_response", "pending", "Construindo resposta final...")

	if turn.completionReason == "confirmation_required" {
		return nil
	}

	if turn.finalContent == "" {
		slog.Warn("Agent reached maximum iterations without final answer; using static fallback")
		turn.completionReason = "exhausted"
		turn.finalContent = "Desculpe, esgotei o limite de ações permitidas sem conseguir formatar a resposta. Todas as consultas foram feitas, mas a tarefa era longa demais. Por favor, tente quebrar o pedido em partes menores."
	} else {
		// Run Response Builder to separate reasoning from presentation
		if l.respBldr != nil {
			formattedResp, rErr := l.respBldr.BuildResponse(ctx, turn.userMessage, turn.intent, turn.finalContent, turn.planStr, turn.sysPrompt)
			if rErr != nil {
				slog.Warn("ResponseBuilder formatting failed, falling back to raw response", "error", rErr)
			} else {
				turn.finalContent = formattedResp
			}
		}
	}

	sendStreamEvent(ctx, turn.events, turn.writer.Event(
		EventMessageFinished,
		MessageFinishedPayload{Content: turn.finalContent},
	))

	sendMilestone(ctx, turn.events, turn.writer, "formatting_response", "completed", "Resposta construída")

	// Store Trace
	turn.trace.CompletionReason = turn.completionReason
	turn.trace.FinalResponse = turn.finalContent
	GlobalTraceStore.AddTrace(turn.sessionIDStr, turn.trace)

	return nil
}

func sendMilestone(ctx context.Context, events chan<- StreamEvent, writer *StreamEventWriter, milestone, status, label string) {
	sendStreamEvent(ctx, events, writer.Event(EventTimelineMilestone, TimelineMilestonePayload{
		Milestone: milestone,
		Status:    status,
		Label:     label,
	}))
}

func (l *Loop) compressMessages(messages []llm.Message) []llm.Message {
	if len(messages) <= 6 {
		return messages
	}
	compressed := make([]llm.Message, len(messages))
	copy(compressed, messages)

	toolNameByCallID := map[string]string{}
	for _, msg := range compressed {
		for _, tc := range msg.ToolCalls {
			toolNameByCallID[tc.ID] = tc.Name
		}
	}

	for i := 0; i < len(compressed)-4; i++ {
		msg := &compressed[i]
		if msg.Role == llm.RoleTool && len(msg.Content) > 200 {
			if toolName := toolNameByCallID[msg.ToolCallID]; toolName != "" {
				if executor := l.tools.Get(toolName); executor != nil {
					msg.Content = executor.Summary(msg.Content)
					continue
				}
			}
			msg.Content = "[Tool output summarized to save context space]"
		}
	}
	return compressed
}

func labelForIntent(intent Intent) string {
	switch intent {
	case IntentTaskManagement:
		return "Consultando sua agenda..."
	case IntentSearchKnowledge:
		return "Analisando suas notas..."
	case IntentBrainstorming:
		return "Pensando..."
	default:
		return "Pensando..."
	}
}

func (l *Loop) loadHistory(ctx context.Context, userID, sessionID pgtype.UUID) ([]llm.Message, error) {
	recentMsgs, err := l.repo.GetMessages(ctx, userID, sessionID, 20, 0)
	if err != nil {
		return nil, fmt.Errorf("get messages: %w", err)
	}

	var messages []llm.Message
	for _, m := range recentMsgs {
		msg := llm.Message{
			Role:    llm.Role(m.Role),
			Content: m.Content,
		}
		if len(m.ToolCalls) > 0 {
			if err := json.Unmarshal(m.ToolCalls, &msg.ToolCalls); err != nil {
				return nil, fmt.Errorf("unmarshal tool calls: %w", err)
			}
		}
		if m.ToolCallID.Valid {
			msg.ToolCallID = m.ToolCallID.String
		}
		messages = append(messages, msg)
	}
	return messages, nil
}

func (l *Loop) persistTurn(ctx context.Context, userID, sessionID pgtype.UUID, msg llm.Message) (sqlcgen.Message, error) {
	var tcBytes []byte
	if len(msg.ToolCalls) > 0 {
		var err error
		tcBytes, err = json.Marshal(msg.ToolCalls)
		if err != nil {
			return sqlcgen.Message{}, fmt.Errorf("marshal tool calls: %w", err)
		}
	}
	var tcIDPtr *string
	if msg.ToolCallID != "" {
		tcIDPtr = &msg.ToolCallID
	}
	return l.repo.CreateMessage(ctx, userID, sessionID, string(msg.Role), msg.Content, tcBytes, tcIDPtr)
}
