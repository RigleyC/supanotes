package sharelinks

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
)

var (
	ErrNotOwner     = errors.New("only the note owner can manage share links")
	ErrLinkNotFound = errors.New("share link not found")
)

type Link struct {
	NoteID  uuid.UUID
	TokenID uuid.UUID
	Enabled bool
	Replace bool
}

type LinkResult struct {
	NoteID  uuid.UUID `json:"note_id"`
	TokenID uuid.UUID `json:"-"`
	Active  bool      `json:"active"`
	URL     string    `json:"url,omitempty"`
}

type PublicNote struct {
	ID       uuid.UUID
	Document []byte
}

// PublicSnapshot is the single public delivery result used by both the HTML
// reader and the native/API reader. The note snapshot is resolved and parsed
// once, after token authorization, so the two transports cannot drift.
type PublicSnapshot struct {
	Note PublicNote
	Page RenderedPage
}

type Repository interface {
	GetOwner(ctx context.Context, noteID uuid.UUID) (uuid.UUID, error)
	GetByNote(ctx context.Context, noteID uuid.UUID) (Link, error)
	Upsert(ctx context.Context, link Link, replace bool) (Link, error)
	Disable(ctx context.Context, noteID uuid.UUID) error
	GetPublicNote(ctx context.Context, tokenID uuid.UUID) (PublicNote, error)
}

type Service struct {
	repo    Repository
	signer  TokenSigner
	baseURL string
}

func NewService(repo Repository, signer TokenSigner, baseURL string) *Service {
	return &Service{
		repo:    repo,
		signer:  signer,
		baseURL: strings.TrimRight(baseURL, "/"),
	}
}

func (s *Service) Activate(ctx context.Context, userID, noteID uuid.UUID, replace bool) (LinkResult, error) {
	if err := s.requireOwner(ctx, userID, noteID); err != nil {
		return LinkResult{}, err
	}

	link, err := s.repo.Upsert(
		ctx,
		Link{NoteID: noteID, TokenID: uuid.New(), Enabled: true},
		replace,
	)
	if err != nil {
		return LinkResult{}, err
	}
	return s.result(link)
}

func (s *Service) Disable(ctx context.Context, userID, noteID uuid.UUID) error {
	if err := s.requireOwner(ctx, userID, noteID); err != nil {
		return err
	}
	return s.repo.Disable(ctx, noteID)
}

func (s *Service) Status(ctx context.Context, userID, noteID uuid.UUID) (LinkResult, error) {
	if err := s.requireOwner(ctx, userID, noteID); err != nil {
		return LinkResult{}, err
	}
	link, err := s.repo.GetByNote(ctx, noteID)
	if errors.Is(err, ErrLinkNotFound) {
		return LinkResult{NoteID: noteID}, nil
	}
	if err != nil {
		return LinkResult{}, err
	}
	if !link.Enabled {
		return LinkResult{NoteID: noteID}, nil
	}
	return s.result(link)
}

func (s *Service) ResolvePublic(ctx context.Context, token string) (PublicNote, error) {
	tokenID, err := s.signer.Verify(token)
	if err != nil {
		return PublicNote{}, ErrLinkNotFound
	}
	note, err := s.repo.GetPublicNote(ctx, tokenID)
	if err != nil {
		if errors.Is(err, ErrLinkNotFound) {
			return PublicNote{}, ErrLinkNotFound
		}
		return PublicNote{}, fmt.Errorf("resolve public note: %w", err)
	}
	return note, nil
}

// PublicSnapshot resolves a token and renders the current canonical snapshot
// for a transport. Rendering errors are returned to the caller instead of
// becoming an empty note.
func (s *Service) PublicSnapshot(ctx context.Context, token string, options RenderOptions) (PublicSnapshot, error) {
	note, err := s.ResolvePublic(ctx, token)
	if err != nil {
		return PublicSnapshot{}, err
	}
	page, err := RenderDocument(note.Document, options)
	if err != nil {
		return PublicSnapshot{}, fmt.Errorf("render public note: %w", err)
	}
	return PublicSnapshot{Note: note, Page: page}, nil
}

func (s *Service) result(link Link) (LinkResult, error) {
	token, err := s.signer.Sign(link.TokenID)
	if err != nil {
		return LinkResult{}, err
	}
	return LinkResult{
		NoteID:  link.NoteID,
		TokenID: link.TokenID,
		Active:  link.Enabled,
		URL:     s.baseURL + "/s/" + token,
	}, nil
}

func (s *Service) requireOwner(ctx context.Context, userID, noteID uuid.UUID) error {
	ownerID, err := s.repo.GetOwner(ctx, noteID)
	if err != nil {
		return err
	}
	if ownerID != userID {
		return ErrNotOwner
	}
	return nil
}
