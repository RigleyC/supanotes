package sync

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Note, error)
	UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error)
	GetSyncTasks(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Task, error)
	UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error)
	GetSyncContexts(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Context, error)
	UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error)
	GetSyncTags(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Tag, error)
	UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error)
	GetSyncTaskCompletions(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.TaskCompletion, error)
	UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error
	GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error)
	UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error
	GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error)
	UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error
	WithQuerier(q sqlcgen.Querier) Repository
}

type repo struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repo{q: q}
}

func (r *repo) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Note, error) {
	return r.q.GetSyncNotes(ctx, sqlcgen.GetSyncNotesParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	return r.q.UpsertNote(ctx, arg)
}

func (r *repo) GetSyncTasks(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Task, error) {
	return r.q.GetSyncTasks(ctx, sqlcgen.GetSyncTasksParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
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

func (r *repo) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	return r.q.UpsertTaskCompletion(ctx, arg)
}

func (r *repo) GetSyncTaskCompletions(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.TaskCompletion, error) {
	return r.q.GetSyncTaskCompletions(ctx, sqlcgen.GetSyncTaskCompletionsParams{
		UserID:       userID,
		LastSyncedAt: lastSyncedAt,
		Limit:        limit,
	})
}

func (r *repo) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	return r.q.GetSyncNoteTags(ctx, sqlcgen.GetSyncNoteTagsParams{UserID: userID})
}

func (r *repo) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	return r.q.UpsertNoteTag(ctx, arg)
}

func (r *repo) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	return r.q.GetSyncNoteLinks(ctx, sqlcgen.GetSyncNoteLinksParams{UserID: userID})
}

func (r *repo) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	return r.q.UpsertNoteLink(ctx, arg)
}

func (r *repo) WithQuerier(q sqlcgen.Querier) Repository {
	return &repo{q: q}
}
