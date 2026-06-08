package gateway

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/rs/zerolog/log"
)

type TelegramClient struct {
	botToken string
	baseURL  string
	repo     *Repository
	http     *http.Client
}

func NewTelegramClient(botToken string) *TelegramClient {
	if botToken == "" {
		log.Warn().Msg("TELEGRAM_BOT_TOKEN is empty — Telegram features disabled")
	}
	return &TelegramClient{
		botToken: botToken,
		baseURL:  fmt.Sprintf("https://api.telegram.org/bot%s", botToken),
		http:     &http.Client{Timeout: 10 * time.Second},
	}
}

func (t *TelegramClient) AttachRepo(repo *Repository) {
	t.repo = repo
}

func (t *TelegramClient) IsEnabled() bool {
	return t.botToken != ""
}

func (t *TelegramClient) SendMessage(chatID int64, text string) error {
	if !t.IsEnabled() {
		return nil
	}

	payload, err := json.Marshal(map[string]any{
		"chat_id":    chatID,
		"text":       text,
		"parse_mode": "Markdown",
	})
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, t.baseURL+"/sendMessage", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := t.http.Do(req)
	if err != nil {
		return fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("telegram returned status %d", resp.StatusCode)
	}
	return nil
}

func (t *TelegramClient) EditMessageText(chatID int64, messageID int64, text string) error {
	if !t.IsEnabled() {
		return nil
	}
	payload, err := json.Marshal(map[string]any{
		"chat_id":    chatID,
		"message_id": messageID,
		"text":       text,
		"parse_mode": "Markdown",
	})
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}
	req, err := http.NewRequest(http.MethodPost, t.baseURL+"/editMessageText", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := t.http.Do(req)
	if err != nil {
		return fmt.Errorf("edit request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("telegram edit returned status %d", resp.StatusCode)
	}
	return nil
}

func (t *TelegramClient) NotifyUser(ctx context.Context, userID pgtype.UUID, text string) error {
	if !t.IsEnabled() || t.repo == nil {
		return nil
	}
	chatID, _, err := t.repo.GetLinkByUserID(ctx, userID)
	if err != nil {
		return err
	}
	return t.SendMessage(chatID, text)
}
