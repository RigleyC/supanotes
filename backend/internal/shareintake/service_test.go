package shareintake

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/linkpreview"
	"github.com/RigleyC/supanotes/internal/noteoperations"
)

type previewStub struct {
	preview *linkpreview.Preview
	err     error
}

func (s previewStub) Fetch(context.Context, string) (*linkpreview.Preview, error) {
	return s.preview, s.err
}

func (previewStub) Metrics() linkpreview.Metrics { return linkpreview.Metrics{} }

type appendStub struct {
	operationID string
	metadata    map[string]any
}

func (s *appendStub) AppendRichLink(
	_ context.Context,
	_ pgtype.UUID,
	_ pgtype.UUID,
	operationID string,
	metadata map[string]any,
) (noteoperations.AppendRichLinkResponse, error) {
	s.operationID = operationID
	s.metadata = metadata
	return noteoperations.AppendRichLinkResponse{Revision: 3}, nil
}

func TestAppendUsesPreviewMetadataAndShareID(t *testing.T) {
	appendStub := &appendStub{}
	svc := NewService(previewStub{preview: &linkpreview.Preview{
		URL:         "https://example.com/post",
		Title:       "Example",
		Description: "A safe link",
		ImageURL:    "https://example.com/image.jpg",
		Domain:      "example.com",
	}}, appendStub)

	result, err := svc.Append(context.Background(), pgtype.UUID{}, pgtype.UUID{}, Request{
		ShareID: "550e8400-e29b-41d4-a716-446655440000",
		URL:     "https://example.com/post",
	})

	require.NoError(t, err)
	require.Equal(t, int64(3), result.Revision)
	require.Equal(t, "550e8400-e29b-41d4-a716-446655440000", appendStub.operationID)
	require.Equal(t, map[string]any{
		"url":         "https://example.com/post",
		"domain":      "example.com",
		"title":       "Example",
		"description": "A safe link",
		"imageUrl":    "https://example.com/image.jpg",
	}, appendStub.metadata)
}

func TestAppendKeepsFallbackWhenPreviewFails(t *testing.T) {
	appendStub := &appendStub{}
	svc := NewService(previewStub{err: errors.New("timeout")}, appendStub)

	_, err := svc.Append(context.Background(), pgtype.UUID{}, pgtype.UUID{}, Request{
		ShareID: "550e8400-e29b-41d4-a716-446655440000",
		URL:     "https://example.com/post",
	})

	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"url":    "https://example.com/post",
		"domain": "example.com",
	}, appendStub.metadata)
}

func TestAppendRejectsNonHTTPURL(t *testing.T) {
	svc := NewService(previewStub{}, &appendStub{})

	_, err := svc.Append(context.Background(), pgtype.UUID{}, pgtype.UUID{}, Request{
		ShareID: "550e8400-e29b-41d4-a716-446655440000",
		URL:     "file:///tmp/example",
	})

	require.ErrorIs(t, err, ErrInvalidURL)
}
