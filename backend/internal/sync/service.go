package sync

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"

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
	Notes               []sqlcgen.GetSyncNotesRow    `json:"notes"`
	NoteNodes           []sqlcgen.NoteNode           `json:"note_nodes"`
	Tasks               []SyncTask                   `json:"tasks"`
	Contexts            []sqlcgen.Context            `json:"contexts"`
	Tags                []sqlcgen.Tag                `json:"tags"`
	TaskCompletions     []sqlcgen.TaskCompletion     `json:"task_completions"`
	NoteTags            []sqlcgen.NoteTag            `json:"note_tags"`
	NoteLinks           []sqlcgen.NoteLink           `json:"note_links"`
	UserNotePreferences []UserNotePreferencePayload `json:"user_note_preferences"`
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

	rawPrefs, err := s.repo.GetSyncUserNotePreferences(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	prefs := make([]UserNotePreferencePayload, len(rawPrefs))
	for i, p := range rawPrefs {
		prefs[i] = toUserNotePreferencePayload(p)
	}

	noteNodes, err := s.repo.GetSyncNoteNodes(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if noteNodes == nil {
		noteNodes = make([]sqlcgen.NoteNode, 0)
	}

	return &SyncPayload{
		Notes:               notes,
		NoteNodes:           noteNodes,
		Tasks:               syncTasks,
		Contexts:            contexts,
		Tags:                tags,
		TaskCompletions:     completions,
		NoteTags:            noteTags,
		NoteLinks:           noteLinks,
		UserNotePreferences: prefs,
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
	// In the new architecture, notes.content can legitimately be empty
	// because the content is stored in note_nodes. We no longer reject
	// notes based on the legacy content field.
	return false
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
	affectedNotes := make(map[pgtype.UUID]bool)

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
				hasView := err == nil && share.Permission == "view"
				if hasView {
					// User has view-only access. We skip updating the note
					// on the server to prevent unauthorized edits, but return
					// success so their client's sync isn't blocked.
					continue
				}
				log.Error().Interface("note_id", n.ID).Interface("user_id", userID).Interface("note_owner_id", n.UserID).Msg("sync push conflict: note edit permission denied")
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
				for j, nt := range payload.NoteTags {
					if nt.NoteID == n.ID {
						payload.NoteTags[j].NoteID = existing.ID
					}
				}
				for j, up := range payload.UserNotePreferences {
					if up.NoteID == n.ID {
						payload.UserNotePreferences[j].NoteID = existing.ID
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
			Content:         "", // Derived automatically by trigger from note_nodes
			IsInbox:         n.IsInbox,
			EmbeddingStatus: embStatus,
			CollapseImages:  n.CollapseImages,
			CreatedAt:       n.CreatedAt,
			DeletedAt:       n.DeletedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				log.Error().Interface("note_id", noteID).Interface("user_id", upsertUserID).Err(err).Msg("sync push conflict: UpsertNote returned ErrNoRows")
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
				log.Error().Interface("task_id", t.ID).Interface("note_id", t.NoteID).Interface("user_id", upsertUserID).Err(err).Msg("sync push conflict: UpsertTask returned ErrNoRows")
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
				log.Error().Interface("context_id", c.ID).Err(err).Msg("sync push conflict: UpsertContext returned ErrNoRows")
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
				log.Error().Interface("tag_id", t.ID).Err(err).Msg("sync push conflict: UpsertTag returned ErrNoRows")
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

	for _, nn := range payload.NoteNodes {
		noteID := nn.NoteID
		canEdit, exists := editableNotes[noteID]
		if !exists {
			note, err := r.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{
				ID:     noteID,
				UserID: userID,
			})
			if err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
						NoteID: noteID,
						UserID: userID,
					})
					if shareErr != nil || share.Permission != "edit" {
						log.Error().Interface("note_id", noteID).Interface("user_id", userID).Msg("sync push conflict: note not owned and share not found/valid for note node")
						return ErrSyncConflict
					}
					canEdit = true
				} else {
					return err
				}
			} else {
				canEdit = note.UserID == userID
			}
			editableNotes[noteID] = canEdit
		}

		if !canEdit {
			log.Error().Interface("note_id", noteID).Interface("user_id", userID).Msg("sync push conflict: user unauthorized to write note node")
			return ErrSyncConflict
		}

		_, err := r.UpsertNoteNode(ctx, sqlcgen.UpsertNoteNodeParams{
			ID:        nn.ID,
			NoteID:    nn.NoteID,
			ParentID:  nn.ParentID,
			Position:  nn.Position,
			Type:      nn.Type,
			Data:      nn.Data,
			CreatedAt: nn.CreatedAt,
			DeletedAt: nn.DeletedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				log.Error().Interface("node_id", nn.ID).Err(err).Msg("sync push conflict: UpsertNoteNode returned ErrNoRows")
				return ErrSyncConflict
			}
			return err
		}
		affectedNotes[nn.NoteID] = true
	}

	for _, p := range payload.UserNotePreferences {
		ownerID, err := r.GetNoteOwnerID(ctx, p.NoteID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				log.Error().Interface("pref_note_id", p.NoteID).Interface("user_id", userID).Err(err).Msg("sync push conflict: GetNoteOwnerID for preference note ID returned ErrNoRows")
				return ErrSyncConflict
			}
			return err
		}
		if ownerID != userID {
			_, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: p.NoteID,
				UserID: userID,
			})
			if shareErr != nil {
				log.Error().Interface("pref_note_id", p.NoteID).Interface("owner_id", ownerID).Interface("user_id", userID).Err(shareErr).Msg("sync push conflict: preference note not owned and share not found/valid")
				return ErrSyncConflict
			}
		}
		_, err = r.UpsertUserNotePreference(ctx, fromUserNotePreferencePayload(p))
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				log.Error().Interface("pref_note_id", p.NoteID).Interface("user_id", userID).Err(err).Msg("sync push conflict: UpsertUserNotePreference returned ErrNoRows")
				return ErrSyncConflict
			}
			return err
		}
	}

	if len(affectedNotes) > 0 {
		noteIDs := make([]pgtype.UUID, 0, len(affectedNotes))
		for id := range affectedNotes {
			noteIDs = append(noteIDs, id)
		}
		if err := r.UpdateNotesContentFromNodes(ctx, noteIDs); err != nil {
			return err
		}
	}

	if tx != nil {
		return tx.Commit(ctx)
	}
	return nil
}
