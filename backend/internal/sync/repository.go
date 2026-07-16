package sync

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.GetSyncNotesRow, error)
	UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error)
	UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error)
	GetSyncContexts(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Context, error)
	UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error)
	GetSyncTags(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Tag, error)
	UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error)
	GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error)
	UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error
	GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error)
	UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error
	GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error)
	GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error)
	GetNoteMeta(ctx context.Context, noteID pgtype.UUID) (sqlcgen.GetNoteMetaRow, error)
	GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error)
	UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error)
	GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error)
	UpsertNotesBatch(ctx context.Context, arg sqlcgen.UpsertNotesBatchParams) error
	UpsertContextsBatch(ctx context.Context, arg sqlcgen.UpsertContextsBatchParams) error
	UpsertTagsBatch(ctx context.Context, arg sqlcgen.UpsertTagsBatchParams) error
	UpsertNoteTagsBatch(ctx context.Context, arg sqlcgen.UpsertNoteTagsBatchParams) error
	UpsertNoteLinksBatch(ctx context.Context, arg sqlcgen.UpsertNoteLinksBatchParams) error
	UpsertNoteYjsState(ctx context.Context, arg sqlcgen.UpsertNoteYjsStateParams) error
	WithQuerier(q sqlcgen.Querier) Repository
}

type repo struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repo{q: q}
}

func (r *repo) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.GetSyncNotesRow, error) {
	return r.q.GetSyncNotes(ctx, sqlcgen.GetSyncNotesParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	return r.q.UpsertNote(ctx, arg)
}

func (r *repo) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	return r.q.UpsertTask(ctx, arg)
}

func (r *repo) GetSyncContexts(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Context, error) {
	return r.q.GetSyncContexts(ctx, sqlcgen.GetSyncContextsParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	return r.q.UpsertContext(ctx, arg)
}

func (r *repo) GetSyncTags(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Tag, error) {
	return r.q.GetSyncTags(ctx, sqlcgen.GetSyncTagsParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	return r.q.UpsertTag(ctx, arg)
}

func (r *repo) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	return r.q.GetSyncNoteTags(ctx, userID)
}

func (r *repo) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	return r.q.UpsertNoteTag(ctx, arg)
}

func (r *repo) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	return r.q.GetSyncNoteLinks(ctx, userID)
}

func (r *repo) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	return r.q.UpsertNoteLink(ctx, arg)
}

func (r *repo) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	return r.q.GetNoteShareForUser(ctx, arg)
}

func (r *repo) GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return r.q.GetNoteOwnerID(ctx, noteID)
}

func (r *repo) GetNoteMeta(ctx context.Context, noteID pgtype.UUID) (sqlcgen.GetNoteMetaRow, error) {
	return r.q.GetNoteMeta(ctx, noteID)
}

func (r *repo) GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error) {
	return r.q.GetSyncUserNotePreferences(ctx, sqlcgen.GetSyncUserNotePreferencesParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
	return r.q.UpsertUserNotePreference(ctx, arg)
}

func (r *repo) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	return r.q.GetNoteByID(ctx, arg)
}

func (r *repo) UpsertNotesBatch(ctx context.Context, arg sqlcgen.UpsertNotesBatchParams) error {
	return r.q.UpsertNotesBatch(ctx, arg)
}

func (r *repo) UpsertContextsBatch(ctx context.Context, arg sqlcgen.UpsertContextsBatchParams) error {
	return r.q.UpsertContextsBatch(ctx, arg)
}

func (r *repo) UpsertTagsBatch(ctx context.Context, arg sqlcgen.UpsertTagsBatchParams) error {
	return r.q.UpsertTagsBatch(ctx, arg)
}

func (r *repo) UpsertNoteTagsBatch(ctx context.Context, arg sqlcgen.UpsertNoteTagsBatchParams) error {
	return r.q.UpsertNoteTagsBatch(ctx, arg)
}

func (r *repo) UpsertNoteLinksBatch(ctx context.Context, arg sqlcgen.UpsertNoteLinksBatchParams) error {
	return r.q.UpsertNoteLinksBatch(ctx, arg)
}

func (r *repo) UpsertNoteYjsState(ctx context.Context, arg sqlcgen.UpsertNoteYjsStateParams) error {
	return r.q.UpsertNoteYjsState(ctx, arg)
}

func (r *repo) WithQuerier(q sqlcgen.Querier) Repository {
	return &repo{q: q}
}
