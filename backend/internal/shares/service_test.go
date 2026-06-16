package shares

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func testUUID() pgtype.UUID {
	return pgtype.UUID{Valid: true}
}

func otherUUID() pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
}

type mockRepository struct {
	ownerID         pgtype.UUID
	ownerErr        error
	user            sqlcgen.User
	userErr         error
	createdShare    sqlcgen.NoteShare
	createShareErr  error
	shares          []sqlcgen.GetNoteSharesRow
	getSharesErr    error
	deleteShareErr  error
}

func (m *mockRepository) GetNoteOwner(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return m.ownerID, m.ownerErr
}

func (m *mockRepository) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	return m.user, m.userErr
}

func (m *mockRepository) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	return m.createdShare, m.createShareErr
}

func (m *mockRepository) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	return m.shares, m.getSharesErr
}

func (m *mockRepository) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	return m.deleteShareErr
}

func TestShareNoteRequiresOwnership(t *testing.T) {
	repo := &mockRepository{
		ownerID: otherUUID(),
	}
	svc := NewService(repo)

	_, err := svc.ShareNote(context.Background(), testUUID(), testUUID(), "friend@example.com", "view")
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("expected ErrNotOwner, got %v", err)
	}
}

func TestShareNoteRejectsSelfShare(t *testing.T) {
	ownerID := testUUID()
	repo := &mockRepository{
		ownerID: ownerID,
		user:    sqlcgen.User{ID: ownerID, Email: "me@example.com"},
	}
	svc := NewService(repo)

	_, err := svc.ShareNote(context.Background(), ownerID, testUUID(), "me@example.com", "view")
	if !errors.Is(err, ErrCannotShareWithSelf) {
		t.Fatalf("expected ErrCannotShareWithSelf, got %v", err)
	}
}

func TestShareNoteCreatesShare(t *testing.T) {
	ownerID := testUUID()
	targetID := otherUUID()
	noteID := testUUID()

	repo := &mockRepository{
		ownerID: ownerID,
		user:    sqlcgen.User{ID: targetID, Email: "friend@example.com", Name: "Friend"},
		createdShare: sqlcgen.NoteShare{
			ID:         testUUID(),
			NoteID:     noteID,
			UserID:     targetID,
			Permission: "view",
		},
	}
	svc := NewService(repo)

	result, err := svc.ShareNote(context.Background(), ownerID, noteID, "friend@example.com", "view")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Permission != "view" {
		t.Fatalf("expected permission view, got %s", result.Permission)
	}
	if result.Email != "friend@example.com" {
		t.Fatalf("expected email friend@example.com, got %s", result.Email)
	}
}

func TestListNoteSharesRequiresOwnership(t *testing.T) {
	repo := &mockRepository{ownerID: otherUUID()}
	svc := NewService(repo)

	_, err := svc.ListNoteShares(context.Background(), testUUID(), testUUID())
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("expected ErrNotOwner, got %v", err)
	}
}

func TestDeleteNoteShareRequiresOwnership(t *testing.T) {
	repo := &mockRepository{ownerID: otherUUID()}
	svc := NewService(repo)

	err := svc.DeleteNoteShare(context.Background(), testUUID(), testUUID(), otherUUID())
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("expected ErrNotOwner, got %v", err)
	}
}

func TestShareNoteReturnsNotFoundWhenNoteMissing(t *testing.T) {
	repo := &mockRepository{ownerErr: pgx.ErrNoRows}
	svc := NewService(repo)

	_, err := svc.ShareNote(context.Background(), testUUID(), testUUID(), "friend@example.com", "view")
	if !errors.Is(err, ErrNoteNotFound) {
		t.Fatalf("expected ErrNoteNotFound, got %v", err)
	}
}

func TestShareNoteReturnsNotFoundWhenUserMissing(t *testing.T) {
	repo := &mockRepository{
		ownerID: testUUID(),
		userErr: pgx.ErrNoRows,
	}
	svc := NewService(repo)

	_, err := svc.ShareNote(context.Background(), testUUID(), testUUID(), "missing@example.com", "view")
	if !errors.Is(err, ErrUserNotFound) {
		t.Fatalf("expected ErrUserNotFound, got %v", err)
	}
}
