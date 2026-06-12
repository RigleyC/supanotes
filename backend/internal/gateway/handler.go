package gateway

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/rs/zerolog/log"

	"github.com/RigleyC/supanotes/internal/web"
)

// AgentBridge is the subset of the agent loop the gateway needs to
// answer a Telegram message. We depend on the interface instead of
// the concrete *agent.Loop so the gateway package has no upward
// import on the agent package.
type AgentBridge interface {
	Chat(ctx context.Context, userID pgtype.UUID, sessionID, message string) (string, error)
}

type LinkCodeResponse struct {
	Code      string `json:"code"`
	ExpiresAt string `json:"expires_at"`
}

type LinkStatusResponse struct {
	Linked   bool   `json:"linked"`
	ChatID   *int64 `json:"chat_id,omitempty"`
	Username string `json:"username,omitempty"`
}

// WebhookUpdate is the slice of the Telegram update envelope we
// actually consume. The full envelope is much richer; we keep the
// decoder minimal on purpose.
type WebhookUpdate struct {
	UpdateID      int64  `json:"update_id"`
	Message       *TgMsg `json:"message,omitempty"`
	EditedMessage *TgMsg `json:"edited_message,omitempty"`
}

type TgUser struct {
	ID           int64  `json:"id"`
	IsBot        bool   `json:"is_bot,omitempty"`
	FirstName    string `json:"first_name,omitempty"`
	Username     string `json:"username,omitempty"`
	LanguageCode string `json:"language_code,omitempty"`
}

type TgMsg struct {
	MessageID int64   `json:"message_id"`
	From      *TgUser `json:"from,omitempty"`
	Chat      TgChat  `json:"chat"`
	Text      string  `json:"text"`
	Date      int64   `json:"date"`
}

type TgChat struct {
	ID       int64  `json:"id"`
	Username string `json:"username,omitempty"`
	Type     string `json:"type"`
}

type Handler struct {
	repo  *Repository
	bot   *TelegramClient
	agent AgentBridge
}

func NewHandler(repo *Repository, bot *TelegramClient, agent AgentBridge) *Handler {
	return &Handler{
		repo:  repo,
		bot:   bot,
		agent: agent,
	}
}

func (h *Handler) GetLinkStatus(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	chatID, username, err := h.repo.GetLinkByUserID(c.Request().Context(), userID)
	if err != nil {
		if errors.Is(err, ErrLinkNotFound) {
			return c.JSON(http.StatusOK, LinkStatusResponse{Linked: false})
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get link status")
	}

	return c.JSON(http.StatusOK, LinkStatusResponse{
		Linked:   true,
		ChatID:   &chatID,
		Username: username,
	})
}

func (h *Handler) GenerateLinkCode(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	code, err := generateCode()
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to generate code")
	}

	expiresAt := time.Now().Add(linkCodeTTL)
	if err := h.repo.CreateLinkCode(c.Request().Context(), userID, code, expiresAt); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to save link code")
	}

	return c.JSON(http.StatusCreated, LinkCodeResponse{
		Code:      code,
		ExpiresAt: expiresAt.Format(time.RFC3339),
	})
}

func (h *Handler) DeleteLink(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	if err := h.repo.DeleteLink(c.Request().Context(), userID); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete link")
	}

	return c.NoContent(http.StatusNoContent)
}

// Webhook receives updates from Telegram. It implements the
// /start <CODE> linking flow and forwards free-form text into the
// user's agent session. The response is always 200 OK so Telegram
// doesn't retry — errors are only logged, never surfaced.
func (h *Handler) Webhook(c echo.Context) error {
	var update WebhookUpdate
	if err := c.Bind(&update); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid update")
	}

	msg := update.Message
	if msg == nil {
		msg = update.EditedMessage
	}
	if msg == nil {
		return c.NoContent(http.StatusOK)
	}

	text := strings.TrimSpace(msg.Text)
	if text == "" {
		return c.NoContent(http.StatusOK)
	}

	ctx := c.Request().Context()

	// /start <CODE> — link flow
	if strings.HasPrefix(text, "/start") {
		parts := strings.Fields(text)
		if len(parts) < 2 {
			h.respond(ctx, msg.Chat.ID,
				"Send /start <CODE> with the code shown in the SupaNotes app to link your account.")
			return c.NoContent(http.StatusOK)
		}
		code := parts[1]
		if err := h.handleStart(ctx, msg, code); err != nil {
			c.Logger().Error(err)
			h.respond(ctx, msg.Chat.ID,
				"That code is invalid, expired, or already used. Generate a new one in the app.")
		}
		return c.NoContent(http.StatusOK)
	}

	// Free-form text — route to agent.
	// Identify the Telegram user via message.from.id (stable), not chat.id (delivery target).
	if msg.From == nil {
		return c.NoContent(http.StatusOK)
	}
	telegramUserID := msg.From.ID

	userID, deliveryChatID, err := h.repo.GetLinkByTelegramUserID(ctx, telegramUserID)
	if err != nil {
		if errors.Is(err, ErrLinkNotFound) {
			h.respond(ctx, msg.Chat.ID,
				"Your Telegram isn't linked to SupaNotes yet. Open the app, go to Settings, and tap Connect Telegram.")
			return c.NoContent(http.StatusOK)
		}
		c.Logger().Error(err)
		return c.NoContent(http.StatusOK)
	}

	// Update delivery chat if the user is messaging from a different chat.
	if deliveryChatID != msg.Chat.ID {
		if err := h.repo.UpdateDeliveryChat(ctx, userID, msg.Chat.ID); err != nil {
			c.Logger().Error(err)
		}
		deliveryChatID = msg.Chat.ID
	}

	if h.agent == nil {
		// Dev mode without the agent loop wired in.
		h.respond(ctx, deliveryChatID, "Agent is not configured on this server.")
		return c.NoContent(http.StatusOK)
	}

	sessionIDStr, err := h.sessionIDForUser(ctx, telegramUserID)
	if err != nil {
		c.Logger().Error(err)
		// Non-fatal — fall back to a fresh session per message.
		sessionIDStr = uuid.New().String()
	}

	reply, err := h.agent.Chat(ctx, userID, sessionIDStr, text)
	if err != nil {
		c.Logger().Error(err)
		h.respond(ctx, deliveryChatID, "Something went wrong. Try again in a moment.")
		return c.NoContent(http.StatusOK)
	}

	if reply == "" {
		return c.NoContent(http.StatusOK)
	}
	h.respond(ctx, deliveryChatID, reply)
	return c.NoContent(http.StatusOK)
}

func (h *Handler) handleStart(ctx context.Context, msg *TgMsg, code string) error {
	userID, expiresAt, used, err := h.repo.GetLinkCode(ctx, code)
	if err != nil {
		return fmt.Errorf("lookup code: %w", err)
	}
	if used || time.Now().After(expiresAt) {
		return ErrLinkCodeExpired
	}
	telegramUserID := int64(0)
	if msg.From != nil {
		telegramUserID = msg.From.ID
	}
	if err := h.repo.CreateLink(ctx, userID, telegramUserID, msg.Chat.ID, msg.Chat.Username); err != nil {
		return fmt.Errorf("create link: %w", err)
	}
	if err := h.repo.UseLinkCode(ctx, code); err != nil {
		return fmt.Errorf("mark used: %w", err)
	}
	h.respond(ctx, msg.Chat.ID,
		"Linked! You can now send messages here and they'll show up in SupaNotes.")
	return nil
}

func (h *Handler) sessionIDForUser(_ context.Context, telegramUserID int64) (string, error) {
	// One session per Telegram user (message.from.id), stable across
	// chats. Reloads reuse the same session row.
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(fmt.Sprintf("tg:%d", telegramUserID))).String(), nil
}

// respond best-effort sends a message back to the chat. Errors are
// only logged because we don't want the webhook to ever return
// non-200 (Telegram would then retry).
func (h *Handler) respond(_ context.Context, chatID int64, text string) {
	if h.bot == nil || !h.bot.IsEnabled() {
		return
	}
	placeholder, err := h.bot.SendMessage(chatID, "Pensando...")
	if err != nil {
		log.Error().Err(err).Int64("chat_id", chatID).Msg("telegram placeholder failed")
		return
	}
	if len(text) > 4096 {
		if err := h.bot.EditMessageText(chatID, placeholder, text[:4096]); err != nil {
			log.Error().Err(err).Int64("chat_id", chatID).Msg("telegram edit first chunk failed")
		}
		for i := 4096; i < len(text); i += 4096 {
			end := i + 4096
			if end > len(text) {
				end = len(text)
			}
			if _, err := h.bot.SendMessage(chatID, text[i:end]); err != nil {
				log.Error().Err(err).Int64("chat_id", chatID).Msg("telegram send chunk failed")
			}
		}
		return
	}
	if err := h.bot.EditMessageText(chatID, placeholder, text); err != nil {
		log.Error().Err(err).Int64("chat_id", chatID).Msg("telegram edit failed")
	}
}

func RegisterRoutes(g *echo.Group, h *Handler) {
	tg := g.Group("/telegram")
	tg.GET("/link", h.GetLinkStatus)
	tg.POST("/link-code", h.GenerateLinkCode)
	tg.DELETE("/link", h.DeleteLink)
}
