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

// SyncPayload is the wire shape for both push (client → server) and
// pull (server → client). The asymmetry between directions lives in
// the server logic, not the type:
//   - On push, the server only reads id / task_id / completed_at from
//     each completion; status is always hardcoded to 'completed' and
//     user_id always comes from the auth context. The client may leave
//     status unset (or set it) and the server ignores it.
//   - On pull, the server returns the full row as stored. The Flutter
//     client stamps user_id locally with the currently authenticated
//     user because the table itself has no user_id column.
type SyncPayload struct {
	Notes           []sqlcgen.GetSyncNotesRow   `json:"notes"`
	Tasks           []SyncTask                  `json:"tasks"`
	Contexts        []sqlcgen.Context           `json:"contexts"`
	Tags            []sqlcgen.Tag               `json:"tags"`
	TaskCompletions []sqlcgen.TaskCompletion    `json:"task_completions"`
	NoteTags        []sqlcgen.NoteTag           `json:"note_tags"`
	NoteLinks       []sqlcgen.NoteLink          `json:"note_links"`
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
		notes = make([]sqlcgen.GetSyncNotesRow, 0)
	}

	tasks, err := s.repo.GetSyncTasks(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if tasks == nil {
		tasks = make([]sqlcgen.Task, 0)
	}
	syncTasks := make([]SyncTask, len(tasks))
	for i, t := range tasks {
		syncTasks[i] = toSyncTask(t)
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

	completions, err := s.repo.GetSyncTaskCompletions(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if completions == nil {
		completions = make([]sqlcgen.TaskCompletion, 0)
	}

	noteTags, err := s.repo.GetSyncNoteTags(ctx, userID)
	if err != nil {
		return nil, err
	}
	if noteTags == nil {
		noteTags = make([]sqlcgen.NoteTag, 0)
	}

	noteLinks, err := s.repo.GetSyncNoteLinks(ctx, userID)
	if err != nil {
		return nil, err
	}
	if noteLinks == nil {
		noteLinks = make([]sqlcgen.NoteLink, 0)
	}

	return &SyncPayload{
		Notes:           notes,
		Tasks:           syncTasks,
		Contexts:        contexts,
		Tags:            tags,
		TaskCompletions: completions,
		NoteTags:        noteTags,
		NoteLinks:       noteLinks,
	}, nil
}

func sanitizeTaskStatus(status string) string {
	switch status {
	case "open", "done":
		return status
	case "completed":
		return "done"
	default:
		return "open"
	}
}

func isEmptyIncomingRegularNote(n sqlcgen.GetSyncNotesRow) bool {
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

	// Track note IDs the authenticated user can edit (owned or shared with edit).
	editableNotes := make(map[pgtype.UUID]bool)

	for i, n := range payload.Notes {
		if isEmptyIncomingRegularNote(n) {
			return ErrEmptyNote
		}

		canEdit := n.UserID == userID
		if !canEdit {
			share, err := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: n.ID,
				UserID: userID,
			})
			canEdit = err == nil && share.Permission == "edit"
			if !canEdit {
				return ErrSyncConflict
			}
		}

		embStatus := n.EmbeddingStatus
		if embStatus == "" {
			embStatus = "pending"
		}
		noteID := n.ID

		if n.IsInbox {
			existing, err := r.GetInboxNote(ctx, userID)
			if err == nil && existing.ID != n.ID {
				noteID = existing.ID
				payload.Notes[i].ID = existing.ID
				for j, t := range payload.Tasks {
					if t.NoteID == n.ID {
						payload.Tasks[j].NoteID = existing.ID
					}
				}
				for j, nl := range payload.NoteLinks {
					if nl.SourceID == n.ID {
						payload.NoteLinks[j].SourceID = existing.ID
					}
					if nl.TargetID == n.ID {
						payload.NoteLinks[j].TargetID = existing.ID
					}
				}
			}
		}
		editableNotes[noteID] = canEdit

		// Preserve the original owner ID for UpsertNote so the
		// WHERE notes.user_id = EXCLUDED.user_id check passes.
		upsertUserID := userID
		if n.UserID != userID {
			upsertUserID = n.UserID
		}

		_, err := r.UpsertNote(ctx, sqlcgen.UpsertNoteParams{
			ID:              noteID,
			UserID:          upsertUserID,
			ContextID:       n.ContextID,
			Title:           n.Title,
			Content:         n.Content,
			IsInbox:         n.IsInbox,
			Favorite:        n.Favorite,
			Archived:        n.Archived,
			EmbeddingStatus: embStatus,
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

	for _, st := range payload.Tasks {
		t, err := fromSyncTask(st)
		if err != nil {
			return err
		}

		status := sanitizeTaskStatus(t.Status)

		upsertUserID := userID
		if t.UserID != userID {
			upsertUserID = t.UserID
		}
		_, err = r.UpsertTask(ctx, sqlcgen.UpsertTaskParams{
			ID:         t.ID,
			UserID:     upsertUserID,
			NoteID:     t.NoteID,
			Title:      t.Title,
			Status:     status,
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

	for _, nt := range payload.NoteTags {
		err := r.UpsertNoteTag(ctx, sqlcgen.UpsertNoteTagParams{
			NoteID: nt.NoteID,
			TagID:  nt.TagID,
			UserID: userID,
		})
		if err != nil {
			return err
		}
	}

	for _, nl := range payload.NoteLinks {
		err := r.UpsertNoteLink(ctx, sqlcgen.UpsertNoteLinkParams{
			ID:        nl.ID,
			SourceID:  nl.SourceID,
			TargetID:  nl.TargetID,
			Relation:  nl.Relation,
			CreatedAt: nl.CreatedAt,
			UserID:    userID,
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
