package sync

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// TaskCompletionInput is the shape the Flutter client pushes for each
// completion row. We deliberately do not reuse sqlcgen.TaskCompletion
// because the client only sends id / task_id / completed_at — status is
// always 'completed' on the server side, and user_id is derived via the
// task FK at insert time.
type TaskCompletionInput struct {
	ID          pgtype.UUID        `json:"id"`
	TaskID      pgtype.UUID        `json:"task_id"`
	CompletedAt pgtype.Timestamptz `json:"completed_at"`
}

type SyncPayload struct {
	Notes           []sqlcgen.Note        `json:"notes"`
	Tasks           []sqlcgen.Task        `json:"tasks"`
	Contexts        []sqlcgen.Context     `json:"contexts"`
	Tags            []sqlcgen.Tag         `json:"tags"`
	TaskCompletions []TaskCompletionInput `json:"task_completions"`
}

type Service interface {
	Pull(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) (*SyncPayload, error)
	Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error
}

var (
	ErrSyncConflict = errors.New("sync conflict")
	ErrEmptyNote    = errors.New("empty note")
)

type service struct {
	repo Repository
	pool *pgxpool.Pool
}

func NewService(repo Repository, pool *pgxpool.Pool) Service {
	return &service{repo: repo, pool: pool}
}

func (s *service) Pull(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) (*SyncPayload, error) {
	notes, err := s.repo.GetSyncNotes(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if notes == nil {
		notes = make([]sqlcgen.Note, 0)
	}

	tasks, err := s.repo.GetSyncTasks(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if tasks == nil {
		tasks = make([]sqlcgen.Task, 0)
	}

	contexts, err := s.repo.GetSyncContexts(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if contexts == nil {
		contexts = make([]sqlcgen.Context, 0)
	}

	tags, err := s.repo.GetSyncTags(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if tags == nil {
		tags = make([]sqlcgen.Tag, 0)
	}

	return &SyncPayload{
		Notes:    notes,
		Tasks:    tasks,
		Contexts: contexts,
		Tags:     tags,
	}, nil
}

func isEmptyIncomingRegularNote(n sqlcgen.Note) bool {
	return !n.IsInbox &&
		!n.DeletedAt.Valid &&
		(!n.Title.Valid || strings.TrimSpace(n.Title.String) == "") &&
		strings.TrimSpace(n.Content) == ""
}

func (s *service) Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error {
	r := s.repo
	var tx pgx.Tx

	if s.pool != nil {
		var err error
		tx, err = s.pool.Begin(ctx)
		if err != nil {
			return err
		}
		defer tx.Rollback(ctx)
		r = s.repo.WithQuerier(sqlcgen.New(tx))
	}

	for _, n := range payload.Notes {
		if isEmptyIncomingRegularNote(n) {
			return ErrEmptyNote
		}
		_, err := r.UpsertNote(ctx, sqlcgen.UpsertNoteParams{
			ID:              n.ID,
			UserID:          userID,
			ContextID:       n.ContextID,
			Title:           n.Title,
			Content:         n.Content,
			IsInbox:         n.IsInbox,
			Favorite:        n.Favorite,
			Archived:        n.Archived,
			EmbeddingStatus: n.EmbeddingStatus,
			CreatedAt:       n.CreatedAt,
			DeletedAt:       n.DeletedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrSyncConflict
			}
			return err
		}
	}

	for _, t := range payload.Tasks {
		_, err := r.UpsertTask(ctx, sqlcgen.UpsertTaskParams{
			ID:         t.ID,
			UserID:     userID,
			NoteID:     t.NoteID,
			Title:      t.Title,
			Status:     t.Status,
			Position:   t.Position,
			Recurrence: t.Recurrence,
			DueDate:    t.DueDate,
			CreatedAt:  t.CreatedAt,
			DeletedAt:  t.DeletedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrSyncConflict
			}
			return err
		}
	}

	for _, c := range payload.Contexts {
		_, err := r.UpsertContext(ctx, sqlcgen.UpsertContextParams{
			ID:        c.ID,
			UserID:    userID,
			Slug:      c.Slug,
			Name:      c.Name,
			CreatedAt: c.CreatedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrSyncConflict
			}
			return err
		}
	}

	for _, t := range payload.Tags {
		_, err := r.UpsertTag(ctx, sqlcgen.UpsertTagParams{
			ID:        t.ID,
			UserID:    userID,
			Name:      t.Name,
			CreatedAt: t.CreatedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrSyncConflict
			}
			return err
		}
	}

	for _, c := range payload.TaskCompletions {
		err := r.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
			ID:          c.ID,
			TaskID:      c.TaskID,
			CompletedAt: c.CompletedAt,
			UserID:      userID,
		})
		if err != nil {
			return err
		}
	}

	if tx != nil {
		return tx.Commit(ctx)
	}
	return nil
}
