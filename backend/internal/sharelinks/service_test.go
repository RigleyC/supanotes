package sharelinks

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
)

func TestServiceActivationRequiresOwner(t *testing.T) {
	noteID := uuid.New()
	ownerID := uuid.New()
	repo := &fakeRepository{ownerID: ownerID}
	svc := NewService(repo, NewTokenSigner("secret"), "https://notes.example")

	_, err := svc.Activate(context.Background(), uuid.New(), noteID, false)
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("error: got %v, want ErrNotOwner", err)
	}
	if repo.upsertCalls != 0 {
		t.Fatalf("upsert calls: got %d, want 0", repo.upsertCalls)
	}
}

func TestServiceActivationCreatesShareLink(t *testing.T) {
	noteID := uuid.New()
	ownerID := uuid.New()
	repo := &fakeRepository{ownerID: ownerID}
	svc := NewService(repo, NewTokenSigner("secret"), "https://notes.example")

	result, err := svc.Activate(context.Background(), ownerID, noteID, false)
	if err != nil {
		t.Fatalf("activate: %v", err)
	}
	if result.URL == "" || result.TokenID == uuid.Nil {
		t.Fatalf("result: %#v", result)
	}
	if repo.upsertCalls != 1 || !repo.lastEnabled {
		t.Fatalf("upsert: calls=%d enabled=%t", repo.upsertCalls, repo.lastEnabled)
	}
	if _, err := svc.signer.Verify(result.URL[len("https://notes.example/s/"):]); err != nil {
		t.Fatalf("verify returned URL token: %v", err)
	}
}

func TestServiceReplacementCreatesNewToken(t *testing.T) {
	noteID := uuid.New()
	ownerID := uuid.New()
	activeID := uuid.New()
	repo := &fakeRepository{ownerID: ownerID, link: Link{NoteID: noteID, TokenID: activeID, Enabled: true}}
	svc := NewService(repo, NewTokenSigner("secret"), "https://notes.example")

	result, err := svc.Activate(context.Background(), ownerID, noteID, true)
	if err != nil {
		t.Fatalf("replace: %v", err)
	}
	if result.TokenID == activeID {
		t.Fatal("replacement reused the active token")
	}
	if repo.lastTokenID == activeID {
		t.Fatal("repository received the old token")
	}
}

type fakeRepository struct {
	ownerID     uuid.UUID
	link        Link
	upsertCalls int
	lastTokenID uuid.UUID
	lastEnabled bool
	publicNote  PublicNote
}

func (r *fakeRepository) GetPublicNote(context.Context, uuid.UUID) (PublicNote, error) {
	return r.publicNote, nil
}

func (r *fakeRepository) GetOwner(context.Context, uuid.UUID) (uuid.UUID, error) {
	return r.ownerID, nil
}

func (r *fakeRepository) GetByNote(context.Context, uuid.UUID) (Link, error) {
	if r.link.TokenID == uuid.Nil {
		return Link{}, ErrLinkNotFound
	}
	return r.link, nil
}

func (r *fakeRepository) Upsert(_ context.Context, link Link) (Link, error) {
	r.upsertCalls++
	r.lastTokenID = link.TokenID
	r.lastEnabled = link.Enabled
	r.link = link
	return link, nil
}

func (r *fakeRepository) Disable(context.Context, uuid.UUID) error {
	r.link.Enabled = false
	return nil
}
