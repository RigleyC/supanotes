package routines

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/robfig/cron/v3"
	"github.com/rs/zerolog/log"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

// Notifier is the subset of the FCM sender the runner needs. It is
// satisfied by *notifications.MultiDeviceSender and by NoopSender in
// dev. Kept here as an interface to avoid an upward import.
type Notifier interface {
	Send(ctx context.Context, userID, title, body string) error
}

// TelegramNotifier is the optional Telegram side of the same flow.
// When nil the runner silently skips it.
type TelegramNotifier interface {
	NotifyUser(ctx context.Context, userID pgtype.UUID, text string) error
}

type Runner struct {
	repo         Repository
	agentCtxBldr ContextBuilder
	llmFactory   llm.Factory
	notifier     Notifier
	telegram     TelegramNotifier
	cronJob      *cron.Cron
	parser       cron.Parser
	mu           sync.Mutex
	active       map[string]bool
}

func NewRunner(
	repo Repository,
	agentCtxBldr ContextBuilder,
	llmFactory llm.Factory,
	notifier Notifier,
	telegram TelegramNotifier,
) *Runner {
	r := &Runner{
		repo:         repo,
		agentCtxBldr: agentCtxBldr,
		llmFactory:   llmFactory,
		notifier:     notifier,
		telegram:     telegram,
		cronJob:      cron.New(),
		parser:       cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow),
		active:       make(map[string]bool),
	}
	r.cronJob.AddFunc("* * * * *", r.tick)
	return r
}

func (r *Runner) Start() {
	r.cronJob.Start()
	log.Info().Msg("routine runner started")
}

func (r *Runner) Stop() {
	r.cronJob.Stop()
}

func (r *Runner) tick() {
	ctx := context.Background()
	routines, err := r.repo.GetEnabledRoutines(ctx)
	if err != nil {
		log.Error().Err(err).Msg("failed to get enabled routines")
		return
	}

	now := time.Now().Truncate(time.Minute)

	for _, rt := range routines {
		schedule, err := r.parser.Parse(rt.CronExpr)
		if err != nil {
			log.Warn().Str("routine_id", fmt.Sprintf("%v", rt.ID)).Err(err).Msg("invalid cron expression")
			continue
		}

		loc, err := time.LoadLocation(rt.Timezone)
		if err != nil {
			loc = time.UTC
		}

		nowInLoc := now.In(loc)
		oneMinAgo := nowInLoc.Add(-1 * time.Minute)
		nextRun := schedule.Next(oneMinAgo).Truncate(time.Minute)

		if nextRun.Equal(nowInLoc) {
			go r.runRoutine(rt)
		}
	}

	// Daily at UTC midnight: clean up old messages + tombstone garbage.
	if now.In(time.UTC).Hour() == 0 && now.In(time.UTC).Minute() == 0 {
		go func() {
			if err := r.repo.CleanupOldMessages(context.Background()); err != nil {
				log.Error().Err(err).Msg("failed to cleanup old messages")
			}
			if err := r.repo.HardDeleteExpired(context.Background()); err != nil {
				log.Error().Err(err).Msg("failed to hard-delete expired records")
			}
		}()
	}
}

func (r *Runner) runRoutine(rt sqlcgen.GetEnabledRoutinesRow) {
	key := fmt.Sprintf("%v", rt.ID)
	r.mu.Lock()
	if r.active[key] {
		r.mu.Unlock()
		return
	}
	r.active[key] = true
	r.mu.Unlock()

	defer func() {
		r.mu.Lock()
		delete(r.active, key)
		r.mu.Unlock()
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	log.Info().Str("routine_id", fmt.Sprintf("%v", rt.ID)).Str("type", rt.Type).Msg("running routine")

	ragContext, err := r.agentCtxBldr.BuildForRoutine(ctx, rt.UserID, rt.Type)
	if err != nil {
		errMsg := err.Error()
		r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "failed", nil, &errMsg)
		return
	}

	sysPrompt := buildBriefPrompt(rt.Type, ragContext)

	llmClient := r.llmFactory.For(llm.TaskTypeAgentic)
	req := llm.Request{
		System:   sysPrompt,
		Messages: []llm.Message{{Role: "user", Content: "Gere a rotina agora."}},
	}

	resp, err := llmClient.Complete(ctx, req)
	if err != nil {
		errMsg := err.Error()
		r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "failed", nil, &errMsg)
		return
	}

	content := resp.Content
	if _, err := r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "success", &content, nil); err != nil {
		log.Error().Err(err).Msg("failed to save routine log")
		return
	}

	// Notify the user. We do both push and Telegram and never let
	// either fail the other; the brief was already saved.
	userIDStr := fmt.Sprintf("%v", rt.UserID)

	if r.notifier != nil {
		title := "Novo brief disponível"
		body := briefPreview(content)
		if err := r.notifier.Send(ctx, userIDStr, title, body); err != nil {
			log.Error().Err(err).Str("user_id", userIDStr).Msg("push notification failed")
		}
	}
	if r.telegram != nil {
		if err := r.telegram.NotifyUser(ctx, rt.UserID, content); err != nil {
			log.Error().Err(err).Str("user_id", userIDStr).Msg("telegram notify failed")
		}
	}
}

// briefPreview returns the first 200 chars of the brief body for
// the push notification payload. The full body still goes out via
// Telegram.
func briefPreview(body string) string {
	if len(body) <= 200 {
		return body
	}
	return body[:199] + "…"
}
