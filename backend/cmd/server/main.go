package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	echomw "github.com/labstack/echo/v4/middleware"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/go-playground/validator/v10"

	"github.com/RigleyC/supanotes/internal/agent"
	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/contexts"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/embeddings"
	"github.com/RigleyC/supanotes/internal/gateway"
	"github.com/RigleyC/supanotes/internal/handler"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/notifications"
	"github.com/RigleyC/supanotes/internal/routines"
	"github.com/RigleyC/supanotes/internal/search"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/soul"
	syncpkg "github.com/RigleyC/supanotes/internal/sync"
	"github.com/RigleyC/supanotes/internal/tags"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/db"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/migrate"
	"github.com/robfig/cron/v3"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal().Err(err).Msg("failed to load config")
	}

	setupLogger(cfg)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := connectDB(ctx, cfg)
	if err != nil {
		log.Fatal().Err(err).Msg("database setup failed")
	}
	if pool != nil {
		defer pool.Close()
	}

	e := echo.New()
	e.Validator = &CustomValidator{validator: validator.New(validator.WithRequiredStructEnabled())}
	e.HideBanner = true
	e.HidePort = true

	e.Use(echomw.RequestID())
	e.Use(echomw.Recover())
	e.Use(echomw.LoggerWithConfig(echomw.LoggerConfig{
		Format: `{"time":"${time_rfc3339}","id":"${id}","method":"${method}","uri":"${uri}","status":${status},"latency":"${latency_human}","error":"${error}"}` + "\n",
	}))
	if len(cfg.CORSOrigins) > 0 {
		e.Use(echomw.CORSWithConfig(echomw.CORSConfig{
			AllowOrigins: cfg.CORSOrigins,
			AllowMethods: []string{http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete},
			AllowHeaders: []string{echo.HeaderOrigin, echo.HeaderContentType, echo.HeaderAuthorization},
		}))
		log.Info().Strs("cors_origins", cfg.CORSOrigins).Msg("CORS enabled")
	}

	registerRoutes(e, cfg, pool)

	go func() {
		log.Info().Str("addr", cfg.Addr()).Str("env", cfg.Environment).Msg("supanotes backend starting")
		if err := e.Start(cfg.Addr()); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal().Err(err).Msg("server failed")
		}
	}()

	<-ctx.Done()
	log.Info().Msg("shutdown signal received")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := e.Shutdown(shutdownCtx); err != nil {
		log.Error().Err(err).Msg("graceful shutdown failed")
		os.Exit(1)
	}

	log.Info().Msg("server stopped cleanly")
}

type CustomValidator struct {
	validator *validator.Validate
}

func (cv *CustomValidator) Validate(i any) error {
	return cv.validator.Struct(i)
}

func setupLogger(cfg *config.Config) {
	zerolog.TimeFieldFormat = time.RFC3339

	if cfg.IsDev() {
		log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stderr, TimeFormat: time.RFC3339})
	} else {
		log.Logger = zerolog.New(os.Stderr).With().Timestamp().Logger()
	}
}

func connectDB(ctx context.Context, cfg *config.Config) (*pgxpool.Pool, error) {
	if cfg.DatabaseURL == "" {
		log.Warn().Msg("DATABASE_URL is empty — starting without database (auth endpoints will 500)")
		return nil, nil
	}

	if err := migrate.Up(cfg.DatabaseURL, "db/migrations"); err != nil {
		return nil, err
	}

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}
	log.Info().Msg("database pool ready")
	return pool, nil
}

func registerRoutes(e *echo.Echo, cfg *config.Config, pool *pgxpool.Pool) {
	api := e.Group("/api/v1")
	api.GET("/health", handler.Health)

	if pool == nil {
		log.Warn().Msg("skipping /auth routes (no DB)")
		return
	}

	queries := sqlcgen.New(pool)
	authSvc := auth.NewService(queries, cfg, pool)
	authH := auth.NewHandler(authSvc)

	api.POST("/auth/register", authH.Register)
	api.POST("/auth/login", authH.Login)
	api.POST("/auth/refresh", authH.Refresh)
	api.POST("/auth/logout", authH.Logout)

	protected := api.Group("")
	protected.Use(auth.JWT(cfg))

	// Contexts
	ctxSvc := contexts.NewService(queries)
	ctxH := contexts.NewHandler(ctxSvc)
	protected.GET("/contexts", ctxH.List)
	protected.POST("/contexts", ctxH.Create)
	protected.DELETE("/contexts/:id", ctxH.Delete)

	// Tags
	tagsSvc := tags.NewService(queries)
	tagsH := tags.NewHandler(tagsSvc)
	protected.GET("/tags", tagsH.List)
	protected.POST("/tags", tagsH.Create)
	protected.DELETE("/tags/:id", tagsH.Delete)

	// Notes
	notesRepo := notes.NewRepository(queries)
	notesSvc := notes.NewService(notesRepo)
	notesH := notes.NewHandler(notesSvc)
	protected.POST("/notes", notesH.Create)
	protected.GET("/notes", notesH.List)
	protected.GET("/notes/:id", notesH.Get)
	protected.PATCH("/notes/:id", notesH.Update)
	protected.DELETE("/notes/:id", notesH.Delete)

	protected.GET("/notes/inbox", notesH.GetInbox)
	protected.POST("/notes/inbox/append", notesH.AppendToInbox)
	protected.POST("/notes/inbox/organize/plan", notesH.PlanOrganization)
	protected.POST("/notes/inbox/organize/apply", notesH.ApplyOrganization)
	protected.POST("/notes/:id/tags", notesH.AddTag)
	protected.DELETE("/notes/:id/tags/:tagId", notesH.RemoveTag)

	// Tasks
	tasksRepo := tasks.NewRepository(queries)
	tasksSvc := tasks.NewService(tasksRepo)
	tasksH := tasks.NewHandler(tasksSvc)
	protected.POST("/tasks", tasksH.Create)
	protected.GET("/tasks", tasksH.List)
	protected.PATCH("/tasks/:id", tasksH.Update)
	protected.DELETE("/tasks/:id", tasksH.Delete)
	protected.POST("/tasks/:id/complete", tasksH.Complete)
	protected.POST("/tasks/:id/reopen", tasksH.Reopen)
	protected.GET("/tasks/today", tasksH.Today)
	protected.GET("/notes/:id/tasks", tasksH.GetByNoteID)

	// Embeddings worker
	embeddingsRepo := embeddings.NewRepository(queries)
	embeddingClient := llm.NewEmbeddingClient(cfg.OpenAIEmbeddingsAPIKey, cfg.OpenAICompatBaseURL, cfg.OpenAIEmbeddingsModel)
	embeddingsSvc := embeddings.NewService(embeddingsRepo, embeddingClient)
	cronJob := cron.New(cron.WithSeconds())
	cronJob.AddFunc("*/30 * * * * *", func() {
		embeddingsSvc.ProcessPending(context.Background())
	})
	cronJob.Start()

	// Soul
	soulSvc := soul.NewService(queries)
	soulH := soul.NewHandler(soulSvc)
	protected.GET("/soul", soulH.Get)
	protected.PUT("/soul", soulH.Update)

	// Memories
	memoriesRepo := memories.NewRepository(queries)
	memoriesSvc := memories.NewService(memoriesRepo)
	memoriesH := memories.NewHandler(memoriesSvc)
	protected.GET("/memories", memoriesH.List)
	protected.POST("/memories", memoriesH.Create)
	protected.DELETE("/memories/:id", memoriesH.Delete)

	// Search
	searchSvc := search.NewService(queries, embeddingClient)
	searchH := search.NewHandler(searchSvc)
	search.RegisterRoutes(protected, searchH)

	// LLM Factory
	llmFactory := llm.NewFactory(cfg)

	// Agent Context Builder
	agentCtxBldr := agent.NewContextBuilder(queries, tasksSvc, memoriesRepo, embeddingClient)

	// Routines
	routinesRepo := routines.NewRepository(queries)
	routinesSvc := routines.NewService(routinesRepo, agentCtxBldr, llmFactory)
	routinesH := routines.NewHandler(routinesSvc)
	routines.RegisterRoutes(protected, routinesH)

	// Agent Loop (built before the runner so the runner and the
	// gateway can both depend on it).
	agentRepo := agent.NewRepository(queries)
	agentTools := agent.NewToolRegistry(queries, notesSvc, tasksSvc, memoriesSvc, routinesSvc, soulSvc, embeddingClient)
	agentLoop := agent.NewLoop(agentRepo, llmFactory, agentCtxBldr, agentTools)
	agentH := agent.NewHandler(agentLoop, agentRepo)
	protected.POST("/agent/chat", agentH.Chat)
	protected.POST("/agent/chat/stream", agentH.ChatSSE)
	protected.GET("/agent/messages", agentH.ListMessages)
	protected.DELETE("/agent/messages", agentH.DeleteMessages)

	// FCM push + Telegram sender — feed both into the routines runner
	// so a fired brief triggers real notifications.
	pushSender, err := notifications.NewMultiDeviceSender(cfg.FCMCredentialsFile, queries)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to build FCM sender")
	}

	gatewayRepo := gateway.NewRepository(pool)
	gatewayBot := gateway.NewTelegramClient(cfg.TelegramBotToken)
	gatewayBot.AttachRepo(gatewayRepo)

	routinesRunner := routines.NewRunner(routinesRepo, agentCtxBldr, llmFactory, pushSender, gatewayBot)
	routinesRunner.Start()

	// Settings
	settingsSvc := settings.NewService(queries)
	settingsH := settings.NewHandler(settingsSvc)
	protected.GET("/settings", settingsH.Get)
	protected.PUT("/settings", settingsH.Update)

	// Device tokens (FCM push registration)
	notificationsSvc := notifications.NewService(queries)
	notificationsH := notifications.NewHandler(notificationsSvc)
	protected.POST("/device-tokens", notificationsH.RegisterToken)
	protected.DELETE("/device-tokens/:id", notificationsH.DeleteToken)

	// Telegram gateway (uses the agent loop as a bridge for free-form
	// messages; the public webhook is mounted on the unauthenticated
	// `api` group because Telegram's servers do not send our JWT).
	gatewayH := gateway.NewHandler(gatewayRepo, gatewayBot, agentLoop)
	gateway.RegisterRoutes(protected, gatewayH)
	api.POST("/gateway/telegram/webhook", gatewayH.Webhook)

	// Sync (push/pull)
	syncRepo := syncpkg.NewRepository(queries)
	syncSvc := syncpkg.NewService(syncRepo, pool)
	syncH := syncpkg.NewHandler(syncSvc)
	protected.POST("/sync/push", syncH.Push)
	protected.POST("/sync/pull", syncH.Pull)
}
