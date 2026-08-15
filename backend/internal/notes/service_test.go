package notes

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepo struct {
	getNoteByIDFn                func(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error)
	updateNoteFn                 func(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
	upsertUserNotePreferenceFn   func(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error)
	updatePreferencesCalls       int
	updateNotesCalls             int
}

func (m *mockRepo) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockRepo) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
	if m.getNoteByIDFn != nil {
		return m.getNoteByIDFn(ctx, id, userID)
	}
	return sqlcgen.GetNoteByIDRow{}, nil
}
func (m *mockRepo) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	m.updateNotesCalls++
	if m.updateNoteFn != nil {
		return m.updateNoteFn(ctx, arg)
	}
	return sqlcgen.Note{}, nil
}
func (m *mockRepo) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
	m.updatePreferencesCalls++
	if m.upsertUserNotePreferenceFn != nil {
		return m.upsertUserNotePreferenceFn(ctx, arg)
	}
	return sqlcgen.UserNotePreference{}, nil
}
func (m *mockRepo) DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return nil
}
func (m *mockRepo) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	return nil, nil
}
func (m *mockRepo) WithQuerier(q sqlcgen.Querier) Repository {
	return m
}

func TestService_UpdateNote_ContentChange(t *testing.T) {
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	}, nil)

	newContent := "updated content"
	note, err := svc.UpdateNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, &newContent, omitNoteIcon(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_ = note
}

func TestService_UpdateNote_IconChange(t *testing.T) {
	var received sqlcgen.UpdateNoteParams
	svc := NewService(&mockRepo{
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			received = arg
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	}, nil)

	icon := []byte(`{"kind":"emoji","value":"🙂"}`)
	if _, err := svc.UpdateNote(
		context.Background(),
		pgtype.UUID{},
		pgtype.UUID{},
		nil,
		valueNoteIcon(icon),
		nil,
	); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !received.SetNoteIcon.Valid || !received.SetNoteIcon.Bool {
		t.Fatal("icon update did not set the icon flag")
	}
	if string(received.NoteIcon) != string(icon) {
		t.Fatalf("note icon = %s, want %s", received.NoteIcon, icon)
	}
}

func TestCreateNoteRejectsEmptyRegularNote(t *testing.T) {
	svc := NewService(&mockRepo{}, nil)
	userID := pgtype.UUID{Valid: true}

	_, err := svc.CreateNote(context.Background(), userID, "   ")

	if !errors.Is(err, ErrEmptyNote) {
		t.Fatalf("expected ErrEmptyNote, got %v", err)
	}
}

func TestService_UpdatePreferences_ChecksAccessThenUpsertsOwnerRow(t *testing.T) {
	var accessChecked bool
	var received sqlcgen.UpsertUserNotePreferenceParams
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			accessChecked = true
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID}, nil
		},
		upsertUserNotePreferenceFn: func(_ context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
			received = arg
			return sqlcgen.UserNotePreference{
				UserID: arg.UserID, NoteID: arg.NoteID,
				Favorite: arg.Favorite, Archived: arg.Archived,
				HideCompleted: arg.HideCompleted, CollapseImages: arg.CollapseImages,
			}, nil
		},
	}
	svc := NewService(repo, nil)

	id := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	row, err := svc.UpdatePreferences(
		context.Background(), userID, id,
		true, false, true, false,
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !accessChecked {
		t.Fatal("access predicate was not queried")
	}
	if repo.updateNotesCalls != 0 {
		t.Fatal("note update was invoked for a preference change")
	}
	if received.UserID != userID || received.NoteID != id {
		t.Fatal("upsert used a different user or note than the authenticated identity")
	}
	if !received.Favorite || received.Archived || !received.HideCompleted || received.CollapseImages {
		t.Fatalf("upsert params = %+v, want favorite/archived/hide_completed/collapse_images of true/false/true/false", received)
	}
	if !row.Favorite || row.Archived || !row.HideCompleted || row.CollapseImages {
		t.Fatalf("returned row = %+v, want all four fields echoed", row)
	}
}

func TestService_UpdatePreferences_RejectsInaccessibleUser(t *testing.T) {
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{}, pgx.ErrNoRows
		},
	}
	svc := NewService(repo, nil)

	_, err := svc.UpdatePreferences(
		context.Background(),
		pgtype.UUID{Bytes: [16]byte{2}, Valid: true},
		pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
		false, false, false, false,
	)

	if !errors.Is(err, ErrNoteNotFound) {
		t.Fatalf("expected ErrNoteNotFound, got %v", err)
	}
	if repo.updatePreferencesCalls != 0 {
		t.Fatal("preference upsert ran even though access was rejected")
	}
}

func TestService_UpdatePreferences_SharedReadOnlyUserWritesOwnRow(t *testing.T) {
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID, Permission: "view"}, nil
		},
	}
	svc := NewService(repo, nil)

	_, err := svc.UpdatePreferences(
		context.Background(),
		pgtype.UUID{Bytes: [16]byte{3}, Valid: true},
		pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
		false, true, false, true,
	)
	if err != nil {
		t.Fatalf("shared read-only user should be able to write their own preferences: %v", err)
	}
}
