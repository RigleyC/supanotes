package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"runtime/pprof"
	"syscall"
	"time"
	_ "time/tzdata"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	echomw "github.com/labstack/echo/v4/middleware"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/go-playground/validator/v10"

	"github.com/RigleyC/supanotes/internal/alexa"
	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/handler"
	"github.com/RigleyC/supanotes/internal/linkpreview"
	mcpapp "github.com/RigleyC/supanotes/internal/mcp"
	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/platformlinks"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/sharelinks"
	"github.com/RigleyC/supanotes/internal/shares"
	"github.com/RigleyC/supanotes/internal/shoppinglist"
	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/db"
	"github.com/RigleyC/supanotes/pkg/migrate"
	mcpsdk "github.com/modelcontextprotocol/go-sdk/mcp"
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

	cronCtx, cronCancel := context.WithCancel(context.Background())
	defer cronCancel()

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
		Format: `{"time":"${time_rfc3339}","id":"${id}","method":"${method}","route":"${route}","status":${status},"latency":"${latency_human}","error":"${error}"}` + "\n",
	}))
	if len(cfg.CORSOrigins) > 0 {
		e.Use(echomw.CORSWithConfig(echomw.CORSConfig{
			AllowOrigins: cfg.CORSOrigins,
			AllowMethods: []string{http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete},
			AllowHeaders: []string{echo.HeaderOrigin, echo.HeaderContentType, echo.HeaderAuthorization},
		}))
		log.Info().Strs("cors_origins", cfg.CORSOrigins).Msg("CORS enabled")
	}

	registerRoutes(e, cfg, pool, cronCtx)

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

type noopNotifier struct{}

func (noopNotifier) Send(_ context.Context, _, _, _ string) error {
	return nil
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

func registerRoutes(e *echo.Echo, cfg *config.Config, pool *pgxpool.Pool, cronCtx context.Context) {
	e.GET("/debug/goroutine", func(c echo.Context) error {
		c.Response().Header().Set("Content-Type", "text/plain; charset=utf-8")
		c.Response().WriteHeader(http.StatusOK)
		return pprof.Lookup("goroutine").WriteTo(c.Response().Writer, 2)
	})

	api := e.Group("/api/v1")
	api.GET("/health", handler.Health(pool))
	platformLinksH := platformlinks.NewHandler(platformlinks.Config{
		AppleTeamID:                   cfg.AppleTeamID,
		AndroidSHA256CertFingerprints: cfg.AndroidSHA256CertFingerprints,
	})
	e.GET("/.well-known/apple-app-site-association", platformLinksH.AppleAppSiteAssociation)
	e.GET("/.well-known/assetlinks.json", platformLinksH.AssetLinks)

	if pool == nil {
		log.Warn().Msg("skipping /auth routes (no DB)")
		return
	}

	queries := sqlcgen.New(pool)
	authSvc := auth.NewService(queries, cfg, pool)
	authRateLimiter := auth.NewAuthRateLimiter()
	authH := auth.NewHandler(authSvc, authRateLimiter)

	api.POST("/auth/register", authH.Register)
	api.POST("/auth/login", authH.Login)
	api.POST("/auth/refresh", authH.Refresh)
	api.POST("/auth/logout", authH.Logout)

	protected := api.Group("")
	protected.Use(auth.JWT(cfg))
	protected.POST("/auth/revoke-sessions", authH.RevokeAllSessions)

	// Notes
	notesRepo := notes.NewRepository(queries)
	notesSvc := notes.NewService(notesRepo, pool)
	notesH := notes.NewHandler(notesSvc)
	protected.POST("/notes", notesH.Create)
	protected.GET("/notes", notesH.List)
	protected.GET("/notes/:id", notesH.Get)
	protected.PATCH("/notes/:id", notesH.Update)
	protected.PATCH("/notes/:id/preferences", notesH.UpdatePreferences)
	protected.DELETE("/notes/:id", notesH.Delete)

	// Shares
	sharesRepo := shares.NewRepository(queries)
	sharesSvc := shares.NewService(sharesRepo)
	sharesH := shares.NewHandler(sharesSvc)
	protected.POST("/notes/:id/shares", sharesH.ShareNote)
	protected.GET("/notes/:id/shares", sharesH.ListNoteShares)
	protected.DELETE("/notes/:id/shares/:user_id", sharesH.DeleteNoteShare)

	// Share links
	shareLinksRepo := sharelinks.NewRepository(queries)
	shareLinksSvc := sharelinks.NewService(
		shareLinksRepo,
		sharelinks.NewTokenSigner(cfg.ShareLinkSecret),
		cfg.PublicBaseURL,
	)
	shareLinksH := sharelinks.NewHandler(shareLinksSvc)
	protected.GET("/notes/:id/share-link", shareLinksH.Status)
	protected.POST("/notes/:id/share-link", shareLinksH.Activate)
	protected.DELETE("/notes/:id/share-link", shareLinksH.Disable)
	e.GET("/s/:token", shareLinksH.Public)
	api.GET("/s/:token/access", shareLinksH.Access)
	api.GET("/s/:token/document", shareLinksH.PublicDocument)

	// Attachments
	storageBackend, err := attachments.NewS3Storage(
		cfg.S3Endpoint, cfg.S3Region, cfg.S3Bucket,
		cfg.S3AccessKeyID, cfg.S3SecretAccessKey,
	)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to init storage backend")
	}
	attachmentsRepo := attachments.NewRepository(queries)
	attachmentsSvc := attachments.NewService(attachmentsRepo, storageBackend)
	attachmentsH := attachments.NewHandler(attachmentsSvc)
	protected.POST("/attachments/upload", attachmentsH.Upload)
	privateAttachmentsH := attachments.NewPrivateHandler(attachmentsRepo, storageBackend)
	protected.GET("/attachments/:id/content", privateAttachmentsH.Download)
	publicAttachmentsH := attachments.NewPublicHandler(
		attachmentsRepo,
		storageBackend,
		func(ctx context.Context, token string) (pgtype.UUID, error) {
			noteID, err := shareLinksSvc.ResolvePublicID(ctx, token)
			if err != nil {
				if errors.Is(err, sharelinks.ErrLinkNotFound) {
					return pgtype.UUID{}, attachments.ErrPublicLinkNotFound
				}
				return pgtype.UUID{}, err
			}
			return pgtype.UUID{Bytes: noteID, Valid: true}, nil
		},
	)
	e.GET("/s/:token/attachments/:attachment_id", publicAttachmentsH.Download)
	api.GET("/s/:token/attachments/:attachment_id", publicAttachmentsH.Download)

	// Link preview (OG scraping)
	linkPreviewSvc := linkpreview.NewService()
	linkPreviewH := linkpreview.NewHandler(linkPreviewSvc)
	protected.GET("/links/preview", linkPreviewH.Preview)

	// Note Operations (REST OT protocol)
	noteOpsSvc := noteoperations.NewService(noteoperations.NewRepository(pool), pool)
	noteOpsH := noteoperations.NewHandler(noteOpsSvc)
	noteOpsH.RegisterRoutes(protected)

	// External command adapters
	shoppingListSvc := shoppinglist.NewService(notesSvc, noteOpsSvc)
	shoppingListH := shoppinglist.NewHandler(shoppingListSvc)
	protected.POST("/integrations/shopping-list/items", shoppingListH.AddItem)
	alexaH := alexa.NewHandler(
		shoppingListSvc,
		cfg.JWTSecret,
		cfg.AlexaApplicationID,
		authpkg.TokenOptions{Issuer: cfg.JWTIssuer, Audience: cfg.JWTAudience},
	)
	api.POST("/integrations/alexa", alexaH.Handle)
	oauthH := alexa.NewOAuthHandler(authSvc, pool, cfg, authRateLimiter)
	api.GET("/integrations/alexa/oauth/authorize", oauthH.Authorize)
	api.POST("/integrations/alexa/oauth/authorize", oauthH.AuthorizeSubmit)
	api.POST("/integrations/alexa/oauth/token", oauthH.Token)

	// GC cron for hard-deleting old notes
	cronJob := cron.New(cron.WithSeconds())
	cronJob.AddFunc("0 0 * * * *", func() {
		tx, err := pool.Begin(cronCtx)
		if err != nil {
			log.Error().Err(err).Msg("cron: failed to begin tx for GC")
			return
		}
		defer tx.Rollback(cronCtx)

		qtx := queries.WithTx(tx)
		acquired, err := qtx.TryAcquireGCLock(cronCtx)
		if err != nil {
			log.Error().Err(err).Msg("cron: failed to acquire GC lock")
			return
		}

		if acquired {
			log.Info().Msg("cron: acquired GC lock, running hard delete")
			if err := qtx.HardDeleteOldNotes(cronCtx); err != nil {
				log.Error().Err(err).Msg("cron: failed to hard delete old notes")
				return
			}
			if err := tx.Commit(cronCtx); err != nil {
				log.Error().Err(err).Msg("cron: failed to commit GC tx")
			}
		} else {
			log.Debug().Msg("cron: GC lock already held, skipping")
		}
	})
	cronJob.Start()

	// MCP Server
	settingsSvc := settings.NewService(queries)
	mcpServer := mcpapp.NewServer(mcpapp.ServerDependencies{
		Security:         mcpapp.NewSecurityStore(pool),
		Notes:            notesSvc,
		DocumentReader:   noteOpsSvc,
		DocumentCommands: noteOpsSvc,
		Attachments:      attachmentsSvc,
		Shares:           sharesSvc,
		Settings:         settingsSvc,
	})
	mcpHandler := mcpsdk.NewStreamableHTTPHandler(func(req *http.Request) *mcpsdk.Server { return mcpServer }, nil)

	// Personal Token Generation Route
	protected.POST("/auth/mcp-token", mcpapp.GenerateMCPTokenHandler(pool))
	protected.DELETE("/auth/mcp-token/:id", mcpapp.RevokeMCPTokenHandler(pool))
	protected.POST("/auth/mcp-token/:id/rotate", mcpapp.RotateMCPTokenHandler(pool))

	// MCP Streamable HTTP Route. Accept both forms because clients differ on
	// whether they preserve the trailing slash from the configured endpoint.
	mcpWrapped := http.StripPrefix("/api/v1/mcp", mcpHandler)
	mcpEchoHandler := mcpapp.MCPAuth(pool)(func(c echo.Context) error {
		mcpWrapped.ServeHTTP(c.Response(), c.Request())
		return nil
	})
	api.Any("/mcp", mcpEchoHandler)
	api.Any("/mcp/*", mcpEchoHandler)

	// Settings
	settingsH := settings.NewHandler(settingsSvc)
	protected.GET("/settings", settingsH.Get)
	protected.PUT("/settings", settingsH.Update)
}
