package routines

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/robfig/cron/v3"
	"github.com/rs/zerolog/log"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
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
	repo           Repository
	agentCtxBldr   ContextBuilder
	llmFactory     llm.Factory
	notifier       Notifier
	telegram       TelegramNotifier
	cronJob        *cron.Cron
	maintenanceJob *cron.Cron
	sem            chan struct{}
	reloadTicker   *time.Ticker
	stopReload     chan struct{}
}

func NewRunner(
	repo Repository,
	agentCtxBldr ContextBuilder,
	llmFactory llm.Factory,
	notifier Notifier,
	telegram TelegramNotifier,
) *Runner {
	return &Runner{
		repo:           repo,
		agentCtxBldr:   agentCtxBldr,
		llmFactory:     llmFactory,
		notifier:       notifier,
		telegram:       telegram,
		cronJob:        cron.New(),
		maintenanceJob: cron.New(),
		sem:            make(chan struct{}, 10),
	}
}

func (r *Runner) Start() {
	r.reload()

	r.reloadTicker = time.NewTicker(5 * time.Minute)
	r.stopReload = make(chan struct{})
	go func() {
		for {
			select {
			case <-r.reloadTicker.C:
				r.reload()
			case <-r.stopReload:
				return
			}
		}
	}()

	r.maintenanceJob.AddFunc("0 0 * * *", func() {
		ctx := context.Background()
		if err := r.repo.CleanupOldMessages(ctx); err != nil {
			log.Error().Err(err).Msg("failed to cleanup old messages")
		}
		if err := r.repo.HardDeleteExpired(ctx); err != nil {
			log.Error().Err(err).Msg("failed to hard-delete expired records")
		}
	})

	r.cronJob.Start()
	r.maintenanceJob.Start()
	log.Info().Msg("routine runner started")
}

func (r *Runner) Stop() {
	r.cronJob.Stop()
	r.maintenanceJob.Stop()
	if r.stopReload != nil {
		close(r.stopReload)
	}
	if r.reloadTicker != nil {
		r.reloadTicker.Stop()
	}
}

func (r *Runner) reload() {
	ctx := context.Background()
	routines, err := r.repo.GetEnabledRoutines(ctx)
	if err != nil {
		log.Error().Err(err).Msg("failed to load routines")
		return
	}

	for _, entry := range r.cronJob.Entries() {
		r.cronJob.Remove(entry.ID)
	}

	for _, rt := range routines {
		expr := rt.CronExpr
		routine := rt
		_, err := r.cronJob.AddFunc(expr, func() {
			r.sem <- struct{}{}
			defer func() { <-r.sem }()
			r.runRoutine(routine)
		})
		if err != nil {
			log.Warn().Err(err).Str("routine_id", uid.UUIDToString(routine.ID)).Msg("invalid cron expression, skipping routine")
		}
	}
}

func (r *Runner) runRoutine(rt sqlcgen.GetEnabledRoutinesRow) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	log.Info().Str("routine_id", uid.UUIDToString(rt.ID)).Str("type", rt.Type).Msg("running routine")

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

	userIDStr := uid.UUIDToString(rt.UserID)

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
