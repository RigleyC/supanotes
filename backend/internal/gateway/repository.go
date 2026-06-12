package gateway

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
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

func (r *Repository) CreateLink(ctx context.Context, userID pgtype.UUID, telegramUserID, chatID int64, username string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO telegram_links (user_id, telegram_user_id, telegram_chat_id, telegram_username)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (user_id) DO UPDATE
		SET telegram_user_id = EXCLUDED.telegram_user_id,
		    telegram_chat_id = EXCLUDED.telegram_chat_id,
		    telegram_username = EXCLUDED.telegram_username`,
		userID, telegramUserID, chatID, username)
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

func (r *Repository) GetLinkByTelegramUserID(ctx context.Context, telegramUserID int64) (pgtype.UUID, int64, error) {
	var userID pgtype.UUID
	var chatID int64
	err := r.pool.QueryRow(ctx, `
		SELECT user_id, telegram_chat_id FROM telegram_links
		WHERE telegram_user_id = $1`, telegramUserID,
	).Scan(&userID, &chatID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return pgtype.UUID{}, 0, ErrLinkNotFound
		}
		return pgtype.UUID{}, 0, err
	}
	return userID, chatID, nil
}

func (r *Repository) UpdateDeliveryChat(ctx context.Context, userID pgtype.UUID, chatID int64) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE telegram_links SET telegram_chat_id = $2
		WHERE user_id = $1`, userID, chatID)
	return err
}

func (r *Repository) DeleteLink(ctx context.Context, userID pgtype.UUID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM telegram_links WHERE user_id = $1`, userID)
	return err
}
