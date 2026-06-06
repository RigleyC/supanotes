package gateway

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

var (
	ErrLinkCodeExpired = errors.New("link code expired")
	ErrLinkNotFound    = errors.New("telegram link not found")
	ErrAlreadyLinked   = errors.New("telegram already linked")
)

const linkCodeTTL = 10 * time.Minute

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) CreateLinkCode(ctx context.Context, userID pgtype.UUID, code string, expiresAt time.Time) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO telegram_link_codes (user_id, code, expires_at)
		VALUES ($1, $2, $3)`,
		userID, code, expiresAt,
	)
	return err
}

func (r *Repository) GetLinkCode(ctx context.Context, code string) (pgtype.UUID, time.Time, bool, error) {
	var userID pgtype.UUID
	var expiresAt time.Time
	var usedAt *time.Time
	err := r.pool.QueryRow(ctx, `
		SELECT user_id, expires_at, used_at FROM telegram_link_codes
		WHERE code = $1`, code,
	).Scan(&userID, &expiresAt, &usedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return pgtype.UUID{}, time.Time{}, false, ErrLinkCodeExpired
		}
		return pgtype.UUID{}, time.Time{}, false, err
	}
	return userID, expiresAt, usedAt != nil, nil
}

func (r *Repository) UseLinkCode(ctx context.Context, code string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE telegram_link_codes SET used_at = NOW()
		WHERE code = $1 AND used_at IS NULL`, code)
	return err
}

func (r *Repository) CreateLink(ctx context.Context, userID pgtype.UUID, chatID int64, username string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO telegram_links (user_id, telegram_chat_id, telegram_username)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id) DO UPDATE
		SET telegram_chat_id = EXCLUDED.telegram_chat_id,
		    telegram_username = EXCLUDED.telegram_username`,
		userID, chatID, username)
	return err
}

func (r *Repository) GetLinkByUserID(ctx context.Context, userID pgtype.UUID) (int64, string, error) {
	var chatID int64
	var username string
	err := r.pool.QueryRow(ctx, `
		SELECT telegram_chat_id, COALESCE(telegram_username, '') FROM telegram_links
		WHERE user_id = $1`, userID,
	).Scan(&chatID, &username)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, "", ErrLinkNotFound
		}
		return 0, "", err
	}
	return chatID, username, nil
}

func (r *Repository) GetLinkByChatID(ctx context.Context, chatID int64) (pgtype.UUID, error) {
	var userID pgtype.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT user_id FROM telegram_links
		WHERE telegram_chat_id = $1`, chatID,
	).Scan(&userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return pgtype.UUID{}, ErrLinkNotFound
		}
		return pgtype.UUID{}, err
	}
	return userID, nil
}

func (r *Repository) DeleteLink(ctx context.Context, userID pgtype.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM telegram_links WHERE user_id = $1`, userID)
	return err
}

func generateCode() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate code: %w", err)
	}
	return hex.EncodeToString(b), nil
}

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

// AttachRepo gives the client access to the link table so callers
// like the routines runner can ask "send this to the user behind
// <userID>" without first having to look up the chat_id themselves.
func (t *TelegramClient) AttachRepo(repo *Repository) {
	t.repo = repo
}

func (t *TelegramClient) IsEnabled() bool {
	return t.botToken != ""
}

// SendMessage POSTs to api.telegram.org/bot<token>/sendMessage. It
// silently returns nil when the bot token is empty (so a dev server
// without TELEGRAM_BOT_TOKEN doesn't blow up).
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

// NotifyUser looks up the chat_id for the user and sends the message.
// Returns ErrLinkNotFound when the user has not linked Telegram.
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
