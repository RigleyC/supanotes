package routines

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
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
	ctx            context.Context
	repo           Repository
	agentCtxBldr   ContextBuilder
	llmFactory     llm.Factory
	notifier       Notifier
	telegram       TelegramNotifier
	cronJob        *cron.Cron
	maintenanceJob *cron.Cron
	running        sync.Map
	reloadTicker   *time.Ticker
	stopReload     chan struct{}
	mu             sync.Mutex
	entries        map[string]cron.EntryID
}

func NewRunner(
	ctx context.Context,
	repo Repository,
	agentCtxBldr ContextBuilder,
	llmFactory llm.Factory,
	notifier Notifier,
	telegram TelegramNotifier,
) *Runner {
	return &Runner{
		ctx:            ctx,
		repo:           repo,
		agentCtxBldr:   agentCtxBldr,
		llmFactory:     llmFactory,
		notifier:       notifier,
		telegram:       telegram,
		cronJob:        cron.New(),
		maintenanceJob: cron.New(),
		entries:        make(map[string]cron.EntryID),
	}
}

func (r *Runner) Start() {
	r.reload()

	r.reloadTicker = time.NewTicker(5 * time.Minute)
	r.stopReload = make(chan struct{})
	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("panic in routine reloader", "recover", rec)
			}
		}()
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
		if err := r.repo.CleanupOldMessages(r.ctx); err != nil {
			log.Error().Err(err).Msg("failed to cleanup old messages")
		}
		if err := r.repo.HardDeleteExpired(r.ctx); err != nil {
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

// reload reconciles the cron schedule with the database state.
// It only adds new routines and removes deleted/disabled ones, leaving
// unchanged entries in place. Note: edits to a routine's cron expression
// or timezone are not picked up until the routine is removed and re-added
// (e.g. via a delete/recreate or app restart).
func (r *Runner) reload() {
	routines, err := r.repo.GetEnabledRoutines(r.ctx)
	if err != nil {
		log.Error().Err(err).Msg("failed to load routines")
		return
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	seen := make(map[string]struct{}, len(routines))
	for _, rt := range routines {
		id := uid.UUIDToString(rt.ID)
		seen[id] = struct{}{}

		if _, ok := r.entries[id]; ok {
			continue
		}

		expr := fmt.Sprintf("CRON_TZ=%s %s", rt.Timezone, rt.CronExpr)
		routine := rt
		eid, err := r.cronJob.AddFunc(expr, func() {
			r.runRoutine(routine)
		})
		if err != nil {
			log.Warn().Err(err).Str("routine_id", id).Msg("invalid cron expression, skipping routine")
			continue
		}
		r.entries[id] = eid
	}

	for id, eid := range r.entries {
		if _, ok := seen[id]; !ok {
			r.cronJob.Remove(eid)
			delete(r.entries, id)
		}
	}
}

func (r *Runner) runRoutine(rt sqlcgen.GetEnabledRoutinesRow) {
	id := uid.UUIDToString(rt.ID)
	lock := make(chan struct{}, 1)
	if _, loaded := r.running.LoadOrStore(id, lock); loaded {
		log.Warn().Str("routine_id", id).Msg("routine already running, skipping")
		return
	}
	defer r.running.Delete(id)

	ctx, cancel := context.WithTimeout(r.ctx, 5*time.Minute)
	defer cancel()

	log.Info().Str("routine_id", uid.UUIDToString(rt.ID)).Str("type", rt.Type).Msg("running routine")

	ragContext, err := r.agentCtxBldr.BuildForRoutine(ctx, rt.UserID, rt.Type)
	if err != nil {
		errMsg := err.Error()
		if _, logErr := r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "failed", nil, &errMsg); logErr != nil {
			slog.Error("failed to create routine log", "error", logErr)
		}
		return
	}

	sysPrompt := buildBriefPrompt(rt.Type, ragContext)

	loc, err := time.LoadLocation(rt.Timezone)
	if err != nil {
		loc = time.UTC
	}
	now := time.Now().In(loc)
	timezonePrompt := fmt.Sprintf("User's local time: %s\nTimezone: %s\n\n%s", now.Format(time.RFC1123), rt.Timezone, sysPrompt)

	llmClient := r.llmFactory.For(llm.TaskTypeGenerate)
	req := llm.Request{
		System:   timezonePrompt,
		Messages: []llm.Message{{Role: "user", Content: "Gere a rotina agora."}},
	}

	resp, err := llmClient.Complete(ctx, req)
	if err != nil {
		errMsg := err.Error()
		if _, logErr := r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "failed", nil, &errMsg); logErr != nil {
			slog.Error("failed to create routine log", "error", logErr)
		}
		return
	}

	content := resp.Content
	if _, err := r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "success", &content, nil); err != nil {
		log.Error().Err(err).Msg("failed to save routine log")
		return
	}

	if err := r.repo.UpdateRoutineLastRunAt(ctx, rt.ID); err != nil {
		log.Error().Err(err).Msg("failed to update routine last_run_at")
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
