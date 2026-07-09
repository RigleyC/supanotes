package sync

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
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
	SyncedAt            time.Time                   `json:"synced_at,omitempty"`
	Notes               []sqlcgen.GetSyncNotesRow    `json:"notes"`
	NoteNodes           []sqlcgen.NoteNode           `json:"note_nodes"`
	Tasks               []SyncTask                   `json:"tasks"`
	Contexts            []sqlcgen.Context            `json:"contexts"`
	Tags                []sqlcgen.Tag                `json:"tags"`
	TaskCompletions     []sqlcgen.TaskCompletion     `json:"task_completions"`
	NoteTags            []sqlcgen.NoteTag            `json:"note_tags"`
	NoteLinks           []sqlcgen.NoteLink           `json:"note_links"`
	UserNotePreferences []UserNotePreferencePayload `json:"user_note_preferences"`
	NoteYjsStates       []sqlcgen.NoteYjsState       `json:"note_yjs_states"`
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
	repo    Repository
	pool    *pgxpool.Pool
	ydoc    *YDocService
	roomMgr *RoomManager
}

func NewService(repo Repository, pool *pgxpool.Pool, ydoc *YDocService, roomMgr *RoomManager) Service {
	return &service{repo: repo, pool: pool, ydoc: ydoc, roomMgr: roomMgr}
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

	yjsStates, err := s.repo.GetSyncNoteYjsStates(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if yjsStates == nil {
		yjsStates = make([]sqlcgen.NoteYjsState, 0)
	}

	return &SyncPayload{
		SyncedAt:            time.Now().UTC(),
		Notes:               notes,
		NoteNodes:           noteNodes,
		Tasks:               syncTasks,
		Contexts:            contexts,
		Tags:                tags,
		TaskCompletions:     completions,
		NoteTags:            noteTags,
		NoteLinks:           noteLinks,
		UserNotePreferences: prefs,
		NoteYjsStates:       yjsStates,
	}, nil
}

func (s *service) Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error {
	startTotal := time.Now()
	log.Info().Interface("user_id", userID).Int("notes", len(payload.Notes)).Int("nodes", len(payload.NoteNodes)).Int("tasks", len(payload.Tasks)).Msg("PUSH START")

	r := s.repo
	var tx pgx.Tx

	if s.pool != nil {
		startTx := time.Now()
		var err error
		tx, err = s.pool.Begin(ctx)
		if err != nil {
			log.Error().Dur("elapsed", time.Since(startTotal)).Err(err).Msg("PUSH FAIL: pool.Begin")
			return err
		}
		defer tx.Rollback(ctx)
		log.Info().Dur("elapsed", time.Since(startTx)).Msg("PUSH TX BEGIN")
		r = s.repo.WithQuerier(sqlcgen.New(tx))
	}

	// Track note IDs the authenticated user can edit (owned or shared with edit).
	editableNotes := make(map[pgtype.UUID]bool)
	affectedNotes := make(map[pgtype.UUID]bool)

	for _, n := range payload.Notes {
		canEdit, err := s.canEditNote(ctx, r, n.ID, userID, editableNotes)
		if err != nil {
			log.Error().Interface("note_id", n.ID).Interface("user_id", userID).Interface("note_owner_id", n.UserID).Err(err).Msg("sync push conflict: note permission check failed")
			return ErrSyncConflict
		}
		if !canEdit {
			share, shareErr := s.repo.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: n.ID, UserID: userID,
			})
			if shareErr == nil && share.Permission == "view" {
				continue
			}
			log.Error().Interface("note_id", n.ID).Interface("user_id", userID).Interface("note_owner_id", n.UserID).Msg("sync push conflict: note edit permission denied")
			return ErrSyncConflict
		}

		embStatus := n.EmbeddingStatus
		if embStatus == "" {
			embStatus = "pending"
		}
		noteID := n.ID

		editableNotes[noteID] = canEdit

		// Preserve the original owner ID for UpsertNote so the
		// WHERE notes.user_id = EXCLUDED.user_id check passes.
		upsertUserID := userID
		if n.UserID != userID {
			upsertUserID = n.UserID
		}

		_, err = r.UpsertNote(ctx, sqlcgen.UpsertNoteParams{
			ID:              noteID,
			UserID:          upsertUserID,
			ContextID:       n.ContextID,
			Content:         "", // Derived automatically by trigger from note_nodes
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

	// Group nodes and tasks by note for Yjs ingestion.
	nodesByNote := make(map[pgtype.UUID][]sqlcgen.NoteNode)
	for _, nn := range payload.NoteNodes {
		noteID := nn.NoteID
		canEdit, err := s.canEditNote(ctx, r, noteID, userID, editableNotes)
		if err != nil {
			log.Error().Interface("node_id", nn.ID).Interface("note_id", noteID).Interface("user_id", userID).Err(err).Msg("sync push conflict: note node permission check failed")
			return ErrSyncConflict
		}
		if !canEdit {
			log.Error().Interface("node_id", nn.ID).Interface("note_id", noteID).Interface("user_id", userID).Msg("sync push conflict: node unauthorized")
			return ErrSyncConflict
		}
		nodesByNote[noteID] = append(nodesByNote[noteID], nn)
		affectedNotes[noteID] = true
	}
	log.Info().Int("nodes_grouped", len(payload.NoteNodes)).Int("unique_notes", len(nodesByNote)).Msg("PUSH: nodes grouped by note")

	tasksByNote := make(map[pgtype.UUID][]SyncTask)
	for _, st := range payload.Tasks {
		t, err := fromSyncTask(st)
		if err != nil {
			return err
		}
		noteID := t.NoteID
		canEdit, err := s.canEditNote(ctx, r, noteID, userID, editableNotes)
		if err != nil {
			log.Error().Interface("task_id", t.ID).Interface("note_id", noteID).Interface("user_id", userID).Err(err).Msg("sync push conflict: task permission check failed")
			return ErrSyncConflict
		}
		if !canEdit {
			log.Error().Interface("task_id", t.ID).Interface("note_id", noteID).Interface("user_id", userID).Msg("sync push conflict: task unauthorized")
			return ErrSyncConflict
		}
		tasksByNote[noteID] = append(tasksByNote[noteID], st)
		affectedNotes[noteID] = true
	}
	log.Info().Int("tasks_grouped", len(payload.Tasks)).Int("unique_notes", len(tasksByNote)).Msg("PUSH: tasks grouped by note")

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
		startContent := time.Now()
		noteIDs := make([]pgtype.UUID, 0, len(affectedNotes))
		for id := range affectedNotes {
			noteIDs = append(noteIDs, id)
		}
		if err := r.UpdateNotesContentFromNodes(ctx, noteIDs); err != nil {
			log.Error().Dur("elapsed", time.Since(startContent)).Err(err).Msg("PUSH FAIL: UpdateNotesContentFromNodes")
			return err
		}
		log.Info().Dur("elapsed", time.Since(startContent)).Int("notes", len(noteIDs)).Msg("PUSH: UpdateNotesContentFromNodes done")
	}

	if tx != nil {
		startCommit := time.Now()
		if err := tx.Commit(ctx); err != nil {
			log.Error().Dur("elapsed", time.Since(startCommit)).Err(err).Msg("PUSH FAIL: tx.Commit")
			return err
		}
		log.Info().Dur("elapsed", time.Since(startCommit)).Msg("PUSH TX COMMIT")
	}

	if s.ydoc != nil {
		startYjs := time.Now()
		log.Info().Int("affected_notes", len(nodesByNote)).Msg("PUSH YJS: starting ingestion")
		for noteIDUUID, nodes := range nodesByNote {
			tasks := tasksByNote[noteIDUUID]
			noteIDStr := uuid.UUID(noteIDUUID.Bytes).String()
			startNote := time.Now()
			update, err := ProduceUpdateFromRows(ctx, s.pool, noteIDStr, nodes, tasks)
			if err != nil {
				log.Error().Str("note_id", noteIDStr).Dur("elapsed", time.Since(startNote)).Err(err).Msg("PUSH FAIL: ProduceUpdateFromRows")
				return fmt.Errorf("produce update for note %s: %w", noteIDStr, err)
			}
			log.Info().Str("note_id", noteIDStr).Dur("produce_elapsed", time.Since(startNote)).Int("update_bytes", len(update)).Msg("PUSH YJS: update produced")

			startApply := time.Now()
			if err := s.ydoc.ApplyNodeMutation(ctx, noteIDStr, update); err != nil {
				log.Error().Str("note_id", noteIDStr).Dur("elapsed", time.Since(startApply)).Err(err).Msg("PUSH FAIL: ApplyNodeMutation")
				return fmt.Errorf("ingest update for note %s: %w", noteIDStr, err)
			}
			log.Info().Str("note_id", noteIDStr).Dur("apply_elapsed", time.Since(startApply)).Msg("PUSH YJS: mutation applied")

			if s.roomMgr != nil {
				startBroadcast := time.Now()
				s.roomMgr.BroadcastIfActive(noteIDStr, update)
				log.Info().Str("note_id", noteIDStr).Dur("elapsed", time.Since(startBroadcast)).Msg("PUSH YJS: broadcast done")
			}
			log.Info().Str("note_id", noteIDStr).Dur("note_total", time.Since(startNote)).Msg("PUSH YJS: note done")
		}
		log.Info().Dur("yjs_total", time.Since(startYjs)).Msg("PUSH YJS: all notes done")
	}

	log.Info().Dur("total", time.Since(startTotal)).Msg("PUSH DONE")
	return nil
}

func (s *service) canEditNote(ctx context.Context, r Repository, noteID pgtype.UUID, userID pgtype.UUID, editableNotes map[pgtype.UUID]bool) (bool, error) {
	if canEdit, exists := editableNotes[noteID]; exists {
		return canEdit, nil
	}
	ownerID, err := r.GetNoteOwnerID(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: noteID, UserID: userID,
			})
			if shareErr != nil || share.Permission != "edit" {
				editableNotes[noteID] = false
				return false, shareErr
			}
			editableNotes[noteID] = true
			return true, nil
		}
		return false, err
	}
	canEdit := ownerID == userID
	if !canEdit {
		share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
			NoteID: noteID, UserID: userID,
		})
		canEdit = shareErr == nil && share.Permission == "edit"
	}
	editableNotes[noteID] = canEdit
	return canEdit, nil
}
