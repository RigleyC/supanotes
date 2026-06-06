package gateway

import (
	"net/http"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
)

type LinkCodeResponse struct {
	Code      string `json:"code"`
	ExpiresAt string `json:"expires_at"`
}

type LinkStatusResponse struct {
	Linked   bool   `json:"linked"`
	ChatID   *int64 `json:"chat_id,omitempty"`
	Username string `json:"username,omitempty"`
}

type WebhookUpdate struct {
	UpdateID int64 `json:"update_id"`
	Message  *struct {
		MessageID int64 `json:"message_id"`
		Chat      struct {
			ID       int64  `json:"id"`
			Username string `json:"username"`
		} `json:"chat"`
		Text string `json:"text"`
	} `json:"message"`
}

type Handler struct {
	repo *Repository
	bot  *TelegramClient
	v    *validator.Validate
}

func NewHandler(repo *Repository, bot *TelegramClient) *Handler {
	return &Handler{repo: repo, bot: bot, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) GetLinkStatus(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	chatID, username, err := h.repo.GetLinkByUserID(c.Request().Context(), userID)
	if err != nil {
		if err == ErrLinkNotFound {
			return c.JSON(http.StatusOK, LinkStatusResponse{Linked: false})
		}
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get link status"})
	}

	return c.JSON(http.StatusOK, LinkStatusResponse{
		Linked:   true,
		ChatID:   &chatID,
		Username: username,
	})
}

func (h *Handler) GenerateLinkCode(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	code, err := generateCode()
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to generate code"})
	}

	expiresAt := time.Now().Add(linkCodeTTL)
	if err := h.repo.CreateLinkCode(c.Request().Context(), userID, code, expiresAt); err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to save link code"})
	}

	return c.JSON(http.StatusCreated, LinkCodeResponse{
		Code:      code,
		ExpiresAt: expiresAt.Format(time.RFC3339),
	})
}

func (h *Handler) DeleteLink(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	if err := h.repo.DeleteLink(c.Request().Context(), userID); err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to delete link"})
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) Webhook(c echo.Context) error {
	var update WebhookUpdate
	if err := c.Bind(&update); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid update"})
	}

	if update.Message == nil {
		return c.NoContent(http.StatusOK)
	}

	chatID := update.Message.Chat.ID
	text := update.Message.Text
	_ = text
	_ = chatID

	return c.NoContent(http.StatusOK)
}

func RegisterRoutes(g *echo.Group, h *Handler) {
	tg := g.Group("/telegram")
	tg.GET("/link", h.GetLinkStatus)
	tg.POST("/link-code", h.GenerateLinkCode)
	tg.DELETE("/link", h.DeleteLink)

	g.POST("/gateway/telegram/webhook", h.Webhook)
}
