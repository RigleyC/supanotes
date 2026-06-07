package sync

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type SyncPayload struct {
	Notes    []sqlcgen.Note    `json:"notes"`
	Tasks    []sqlcgen.Task    `json:"tasks"`
	Contexts []sqlcgen.Context `json:"contexts"`
	Tags     []sqlcgen.Tag     `json:"tags"`
}

type Service interface {
	Pull(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) (*SyncPayload, error)
	Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error
}

var ErrSyncConflict = errors.New("sync conflict")

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
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

func (s *service) Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error {
	for _, n := range payload.Notes {
		_, err := s.repo.UpsertNote(ctx, sqlcgen.UpsertNoteParams{
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
		_, err := s.repo.UpsertTask(ctx, sqlcgen.UpsertTaskParams{
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
		_, err := s.repo.UpsertContext(ctx, sqlcgen.UpsertContextParams{
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
		_, err := s.repo.UpsertTag(ctx, sqlcgen.UpsertTagParams{
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

	return nil
}
