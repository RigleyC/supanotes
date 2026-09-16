package shareintake

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/linkpreview"
	"github.com/RigleyC/supanotes/internal/noteoperations"
)

var (
	ErrInvalidShareID   = errors.New("invalid share id")
	ErrInvalidURL       = errors.New("url must be an absolute http or https URL")
	ErrInvalidCreatedAt = errors.New("createdAt must be RFC3339")
)

type Request struct {
	ShareID   string `json:"shareId" validate:"required,uuid"`
	URL       string `json:"url" validate:"required,url"`
	CreatedAt string `json:"createdAt,omitempty"`
}

func (r *Request) UnmarshalJSON(data []byte) error {
	trimmed := bytes.TrimSpace(data)
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return errors.New("share intake request must be a JSON object")
	}
	type requestAlias Request
	var value requestAlias
	decoder := json.NewDecoder(bytes.NewReader(trimmed))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&value); err != nil {
		return fmt.Errorf("invalid share intake request: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("invalid share intake request")
	}
	if value.CreatedAt != "" {
		if _, err := time.Parse(time.RFC3339, value.CreatedAt); err != nil {
			return ErrInvalidCreatedAt
		}
	}
	*r = Request(value)
	return nil
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
}

func NewService(previews linkpreview.Service, append AppendService) *Service {
	return &Service{previews: previews, append: append}
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
	if req.CreatedAt != "" {
		if _, err := time.Parse(time.RFC3339, req.CreatedAt); err != nil {
			return noteoperations.AppendRichLinkResponse{}, ErrInvalidCreatedAt
		}
	}
	parsed, err := validateURL(req.URL)
	if err != nil {
		return noteoperations.AppendRichLinkResponse{}, err
	}
	metadata := map[string]any{
		"url":    parsed.String(),
		"domain": parsed.Hostname(),
	}
	if preview, fetchErr := s.previews.Fetch(ctx, parsed.String()); fetchErr == nil {
		metadata["url"] = preview.URL
		metadata["domain"] = preview.Domain
		metadata["previewStatus"] = "ready"
		if preview.Title != "" {
			metadata["title"] = preview.Title
		}
		if preview.Description != "" {
			metadata["description"] = preview.Description
		}
		if preview.ImageURL != "" {
			metadata["imageUrl"] = preview.ImageURL
		}
	} else {
		metadata["previewStatus"] = "failed"
		if ctx.Err() == nil {
			slog.WarnContext(ctx, "link preview fetch failed; storing url metadata only",
				"error_type", fmt.Sprintf("%T", fetchErr))
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
