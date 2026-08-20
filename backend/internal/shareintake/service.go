package shareintake

import (
	"context"
	"errors"
	"net/url"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/linkpreview"
	"github.com/RigleyC/supanotes/internal/noteoperations"
)

var (
	ErrInvalidShareID = errors.New("invalid share id")
	ErrInvalidURL     = errors.New("url must be an absolute http or https URL")
)

type Request struct {
	ShareID   string `json:"shareId" validate:"required,uuid"`
	URL       string `json:"url" validate:"required,url"`
	CreatedAt string `json:"createdAt,omitempty"`
}

type AppendService interface {
	AppendRichLink(
		ctx context.Context,
		noteID pgtype.UUID,
		userID pgtype.UUID,
		operationID string,
		metadata map[string]any,
	) (noteoperations.AppendRichLinkResponse, error)
}

type Service struct {
	previews linkpreview.Service
	append   AppendService
	pool     *pgxpool.Pool
}

func NewService(previews linkpreview.Service, append AppendService) *Service {
	return &Service{previews: previews, append: append}
}

func NewServiceWithPool(previews linkpreview.Service, append AppendService, pool *pgxpool.Pool) *Service {
	return &Service{previews: previews, append: append, pool: pool}
}

func (s *Service) Append(
	ctx context.Context,
	noteID pgtype.UUID,
	userID pgtype.UUID,
	req Request,
) (noteoperations.AppendRichLinkResponse, error) {
	if _, err := uuid.Parse(req.ShareID); err != nil {
		return noteoperations.AppendRichLinkResponse{}, ErrInvalidShareID
	}
	parsed, err := validateURL(req.URL)
	if err != nil {
		return noteoperations.AppendRichLinkResponse{}, err
	}
	if s.pool != nil {
		shareID := uuid.MustParse(req.ShareID)
		queries := sqlcgen.New(s.pool)
		if _, err := queries.ReserveSharedLinkIngestion(ctx, sqlcgen.ReserveSharedLinkIngestionParams{
			UserID:      userID,
			ShareID:     pgtype.UUID{Bytes: shareID, Valid: true},
			NoteID:      noteID,
			OperationID: pgtype.UUID{Bytes: shareID, Valid: true},
		}); err != nil {
			return noteoperations.AppendRichLinkResponse{}, err
		}
	}

	metadata := map[string]any{
		"url":    parsed.String(),
		"domain": parsed.Hostname(),
	}
	if preview, fetchErr := s.previews.Fetch(ctx, parsed.String()); fetchErr == nil {
		metadata["url"] = preview.URL
		metadata["domain"] = preview.Domain
		if preview.Title != "" {
			metadata["title"] = preview.Title
		}
		if preview.Description != "" {
			metadata["description"] = preview.Description
		}
		if preview.ImageURL != "" {
			metadata["imageUrl"] = preview.ImageURL
		}
	}

	return s.append.AppendRichLink(ctx, noteID, userID, req.ShareID, metadata)
}

func validateURL(raw string) (*url.URL, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || !parsed.IsAbs() || parsed.Host == "" {
		return nil, ErrInvalidURL
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, ErrInvalidURL
	}
	if parsed.User != nil {
		return nil, ErrInvalidURL
	}
	return parsed, nil
}
