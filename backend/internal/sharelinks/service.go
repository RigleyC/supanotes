package sharelinks

import (
	"context"
	"errors"
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

type Repository interface {
	GetOwner(ctx context.Context, noteID uuid.UUID) (uuid.UUID, error)
	GetByNote(ctx context.Context, noteID uuid.UUID) (Link, error)
	Upsert(ctx context.Context, link Link) (Link, error)
	Disable(ctx context.Context, noteID uuid.UUID) error
}

type PublicRepository interface {
	GetPublicNote(ctx context.Context, tokenID uuid.UUID) (PublicNote, error)
}

type Service struct {
	repo    Repository
	signer  TokenSigner
	baseURL string
	public  PublicRepository
}

func NewService(repo Repository, signer TokenSigner, baseURL string) *Service {
	service := &Service{repo: repo, signer: signer, baseURL: strings.TrimRight(baseURL, "/")}
	if publicRepo, ok := repo.(PublicRepository); ok {
		service.public = publicRepo
	}
	return service
}

func (s *Service) Activate(ctx context.Context, userID, noteID uuid.UUID, replace bool) (LinkResult, error) {
	if err := s.requireOwner(ctx, userID, noteID); err != nil {
		return LinkResult{}, err
	}
	if existing, err := s.repo.GetByNote(ctx, noteID); err == nil {
		if existing.Enabled && !replace {
			return s.result(existing)
		}
	} else if !errors.Is(err, ErrLinkNotFound) {
		return LinkResult{}, err
	}

	link, err := s.repo.Upsert(ctx, Link{NoteID: noteID, TokenID: uuid.New(), Enabled: true})
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
	if s.public == nil {
		return PublicNote{}, ErrLinkNotFound
	}
	tokenID, err := s.signer.Verify(token)
	if err != nil {
		return PublicNote{}, ErrLinkNotFound
	}
	note, err := s.public.GetPublicNote(ctx, tokenID)
	if err != nil {
		return PublicNote{}, ErrLinkNotFound
	}
	return note, nil
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
