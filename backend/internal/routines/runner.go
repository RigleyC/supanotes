package routines

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/robfig/cron/v3"
	"github.com/rs/zerolog/log"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type Runner struct {
	repo         Repository
	agentCtxBldr ContextBuilder
	llmFactory   llm.Factory
	cronJob      *cron.Cron
	parser       cron.Parser
	mu           sync.Mutex
	active       map[string]bool // keep track of running routines to avoid duplicates
}

func NewRunner(repo Repository, agentCtxBldr ContextBuilder, llmFactory llm.Factory) *Runner {
	r := &Runner{
		repo:         repo,
		agentCtxBldr: agentCtxBldr,
		llmFactory:   llmFactory,
		cronJob:      cron.New(),
		parser:       cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow),
		active:       make(map[string]bool),
	}
	// Verify every minute
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

		// Check timezone
		loc, err := time.LoadLocation(rt.Timezone)
		if err != nil {
			loc = time.UTC
		}
		
		nowInLoc := now.In(loc)
		
		// If schedule matches the current minute (by checking if Next from 1 minute ago is now)
		oneMinAgo := nowInLoc.Add(-1 * time.Minute)
		nextRun := schedule.Next(oneMinAgo).Truncate(time.Minute)

		if nextRun.Equal(nowInLoc) {
			go r.runRoutine(rt)
		}
	}
	
	// Also trigger cleanup of old messages once a day at UTC midnight
	if now.In(time.UTC).Hour() == 0 && now.In(time.UTC).Minute() == 0 {
		go func() {
			err := r.repo.CleanupOldMessages(context.Background())
			if err != nil {
				log.Error().Err(err).Msg("failed to cleanup old messages")
			} else {
				log.Info().Msg("cleaned up old messages")
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

	// Same logic as TestRoutine but saving log
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
	_, err = r.repo.CreateRoutineLog(ctx, rt.ID, rt.UserID, "success", &content, nil)
	if err != nil {
		log.Error().Err(err).Msg("failed to save routine log")
	}

	// Stub: Send Push/Telegram notification
	log.Info().Str("user_id", fmt.Sprintf("%v", rt.UserID)).Msg("STUB: Sending FCM/Telegram push: Novo brief disponível!")
}
