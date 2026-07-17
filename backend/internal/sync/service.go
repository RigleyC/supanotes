package sync

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// SyncPayload is the wire shape for both push (client → server) and
// pull (server → client). task_completions are now derived from the
// YDoc projection and are no longer synced via REST.
type SyncPayload struct {
	SyncedAt            time.Time                   `json:"synced_at,omitempty"`
	Notes               []sqlcgen.GetSyncNotesRow    `json:"notes"`
	Contexts            []sqlcgen.Context            `json:"contexts"`
	Tags                []sqlcgen.Tag                `json:"tags"`
	NoteTags            []sqlcgen.NoteTag            `json:"note_tags"`
	NoteLinks           []sqlcgen.NoteLink           `json:"note_links"`
	UserNotePreferences []UserNotePreferencePayload `json:"user_note_preferences"`
	NoteYjsStates       []NoteYjsStatePayload       `json:"note_yjs_states"`
}

// NoteYjsStatePayload is the wire shape for a Yjs state snapshot pushed
// or pulled via REST.
type NoteYjsStatePayload struct {
	NoteID    string    `json:"note_id"`
	State     []byte    `json:"state"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Service interface {
	Pull(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) (*SyncPayload, error)
	Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error
}

var (
	// ErrSyncConflict indicates a conflict that prevents merging safely, requiring client reconciliation.
	ErrSyncConflict = errors.New("sync conflict")
	ErrNoteDeleted  = errors.New("NOTE_DELETED")
)

type service struct {
	repo Repository
	pool *pgxpool.Pool
	ydoc *YDocService
}

func NewService(repo Repository, pool *pgxpool.Pool, ydoc *YDocService) Service {
	return &service{repo: repo, pool: pool, ydoc: ydoc}
}

func (s *service) Pull(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) (*SyncPayload, error) {
	notes, err := s.repo.GetSyncNotes(ctx, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	if notes == nil {
		notes = make([]sqlcgen.GetSyncNotesRow, 0)
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

	yjsStateRows, err := s.pool.Query(ctx, `
		SELECT ns.note_id::text, ns.state, ns.updated_at
		FROM note_yjs_states ns
		JOIN notes n ON n.id = ns.note_id
		LEFT JOIN note_shares nsh ON nsh.note_id = n.id AND nsh.user_id = $1
		WHERE (n.user_id = $1 OR nsh.user_id = $1)
		AND ($2::timestamptz IS NULL OR ns.updated_at > $2)
		ORDER BY ns.updated_at ASC
		LIMIT $3
	`, userID, lastSyncedAt, limit)
	if err != nil {
		return nil, err
	}
	defer yjsStateRows.Close()

	var yjsStates []NoteYjsStatePayload
	for yjsStateRows.Next() {
		var ys NoteYjsStatePayload
		var updatedAt pgtype.Timestamptz
		if err := yjsStateRows.Scan(&ys.NoteID, &ys.State, &updatedAt); err != nil {
			return nil, err
		}
		ys.UpdatedAt = updatedAt.Time
		yjsStates = append(yjsStates, ys)
	}
	if err := yjsStateRows.Err(); err != nil {
		return nil, err
	}
	if yjsStates == nil {
		yjsStates = make([]NoteYjsStatePayload, 0)
	}

	return &SyncPayload{
		SyncedAt:            time.Now().UTC(),
		Notes:               notes,
		Contexts:            contexts,
		Tags:                tags,
		NoteTags:            noteTags,
		NoteLinks:           noteLinks,
		UserNotePreferences: prefs,
		NoteYjsStates:       yjsStates,
	}, nil
}

func (s *service) Push(ctx context.Context, userID pgtype.UUID, payload *SyncPayload) error {
	startTotal := time.Now()
	slog.Info("PUSH START", "user_id", userID, "notes", len(payload.Notes))

	r := s.repo
	var tx pgx.Tx

	editableNotes := make(map[pgtype.UUID]bool)

	// Pre-populate ownership for notes in this payload so new notes bypass DB checks
	for _, n := range payload.Notes {
		if n.UserID == userID {
			editableNotes[n.ID] = true
		}
	}

	if s.pool != nil {
		if s.ydoc != nil {
			for _, ys := range payload.NoteYjsStates {
				noteUUID, err := parseUUIDStr(ys.NoteID)
				if err != nil {
					slog.Error("sync push: invalid note UUID in Yjs state", "note_id", ys.NoteID, "error", err)
					return err
				}

				canEdit, err := s.canEditNote(ctx, r, noteUUID, userID, editableNotes, false)
				if err != nil {
					if errors.Is(err, ErrNoteDeleted) {
						slog.Error("sync push: Yjs state rejected because note is deleted", "note_id", ys.NoteID, "user_id", userID)
						return ErrNoteDeleted
					}
					slog.Error("sync push: Yjs state permission check failed", "note_id", ys.NoteID, "user_id", userID, "error", err)
					return ErrSyncConflict
				}
				if !canEdit {
					// Note doesn't exist on server yet or user lacks permission.
					// Skip instead of aborting — the note header may be upserted
					// later in this push, and the Yjs state will sync next cycle.
					slog.Warn("sync push: skipping Yjs state for non-editable note", "note_id", ys.NoteID, "user_id", userID)
					continue
				}

				_, err = s.ydoc.DocFor(ctx, ys.NoteID)
				if err != nil {
					slog.Error("sync push: pre-load DocFor failed", "note_id", ys.NoteID, "error", err)
					return err
				}

				if err := s.ydoc.ApplyNodeMutation(ctx, ys.NoteID, ys.State); err != nil {
					slog.Error("sync push: ApplyNodeMutation failed", "note_id", ys.NoteID, "error", err)
					return err
				}
			}
		}

		startTx := time.Now()
		var err error
		tx, err = s.pool.Begin(ctx)
		if err != nil {
			slog.Error("PUSH FAIL: pool.Begin", "elapsed", time.Since(startTotal), "error", err)
			return err
		}
		defer tx.Rollback(ctx)
		slog.Info("PUSH TX BEGIN", "elapsed", time.Since(startTx))
		r = s.repo.WithQuerier(sqlcgen.New(tx))
	}

	// Batch upsert all notes
	{
		var ids, userIDs, contextIDs []pgtype.UUID
		var contents, embStatuses []string
		var collapseImages []bool
		var createdAts, deletedAts []pgtype.Timestamptz
		for _, n := range payload.Notes {
			canEdit, err := s.canEditNote(ctx, r, n.ID, userID, editableNotes, n.DeletedAt.Valid)
			if err != nil {
				if errors.Is(err, ErrNoteDeleted) {
					slog.Error("sync push conflict: note is already deleted", "note_id", n.ID, "user_id", userID)
					return ErrNoteDeleted
				}
				slog.Error("sync push conflict: note permission check failed", "note_id", n.ID, "user_id", userID, "note_owner_id", n.UserID, "error", err)
				return ErrSyncConflict
			}
			if !canEdit && n.UserID == userID {
				canEdit = true
				editableNotes[n.ID] = true
			}
			if !canEdit {
				share, shareErr := s.repo.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{NoteID: n.ID, UserID: userID})
				if shareErr == nil && share.Permission == "view" {
					continue
				}
				slog.Error("sync push conflict: note edit permission denied", "note_id", n.ID, "user_id", userID, "note_owner_id", n.UserID)
				return ErrSyncConflict
			}
			editableNotes[n.ID] = canEdit
			embStatus := n.EmbeddingStatus
			if embStatus == "" {
				embStatus = "pending"
			}
			upsertUserID := userID
			if n.UserID != userID {
				upsertUserID = n.UserID
			}
			ids = append(ids, n.ID)
			userIDs = append(userIDs, upsertUserID)
			contextIDs = append(contextIDs, n.ContextID)
			contents = append(contents, "")
			embStatuses = append(embStatuses, embStatus)
			collapseImages = append(collapseImages, n.CollapseImages)
			createdAts = append(createdAts, n.CreatedAt)
			deletedAts = append(deletedAts, n.DeletedAt)
		}
		if len(ids) > 0 {
			if err := r.UpsertNotesBatch(ctx, sqlcgen.UpsertNotesBatchParams{
				Column1: ids, Column2: userIDs, Column3: contextIDs,
				Column4: contents, Column5: embStatuses, Column6: collapseImages,
				Column7: createdAts, Column8: deletedAts,
			}); err != nil {
				return fmt.Errorf("batch upsert notes: %w", err)
			}
		}
	}

	// Batch upsert all contexts
	{
		var ids, userIDs []pgtype.UUID
		var slugs, names []string
		var createdAts []pgtype.Timestamptz
		for _, c := range payload.Contexts {
			ids = append(ids, c.ID)
			userIDs = append(userIDs, userID)
			slugs = append(slugs, c.Slug)
			names = append(names, c.Name)
			createdAts = append(createdAts, c.CreatedAt)
		}
		if len(ids) > 0 {
			if err := r.UpsertContextsBatch(ctx, sqlcgen.UpsertContextsBatchParams{
				Column1: ids, Column2: userIDs, Column3: slugs, Column4: names, Column5: createdAts,
			}); err != nil {
				return fmt.Errorf("batch upsert contexts: %w", err)
			}
		}
	}

	// Batch upsert all tags
	{
		var ids, userIDs []pgtype.UUID
		var names []string
		var createdAts []pgtype.Timestamptz
		for _, t := range payload.Tags {
			ids = append(ids, t.ID)
			userIDs = append(userIDs, userID)
			names = append(names, t.Name)
			createdAts = append(createdAts, t.CreatedAt)
		}
		if len(ids) > 0 {
			if err := r.UpsertTagsBatch(ctx, sqlcgen.UpsertTagsBatchParams{
				Column1: ids, Column2: userIDs, Column3: names, Column4: createdAts,
			}); err != nil {
				return fmt.Errorf("batch upsert tags: %w", err)
			}
		}
	}

	// Batch upsert all note tags
	{
		var noteIDs, tagIDs []pgtype.UUID
		for _, nt := range payload.NoteTags {
			noteIDs = append(noteIDs, nt.NoteID)
			tagIDs = append(tagIDs, nt.TagID)
		}
		if len(noteIDs) > 0 {
			if err := r.UpsertNoteTagsBatch(ctx, sqlcgen.UpsertNoteTagsBatchParams{
				Column1: noteIDs, Column2: tagIDs,
			}); err != nil {
				return fmt.Errorf("batch upsert note tags: %w", err)
			}
		}
	}

	// Batch upsert all note links
	{
		var ids, sourceIDs, targetIDs []pgtype.UUID
		var relations []string
		var createdAts []pgtype.Timestamptz
		for _, nl := range payload.NoteLinks {
			ids = append(ids, nl.ID)
			sourceIDs = append(sourceIDs, nl.SourceID)
			targetIDs = append(targetIDs, nl.TargetID)
			relations = append(relations, nl.Relation)
			createdAts = append(createdAts, nl.CreatedAt)
		}
		if len(ids) > 0 {
			if err := r.UpsertNoteLinksBatch(ctx, sqlcgen.UpsertNoteLinksBatchParams{
				Column1: ids, Column2: sourceIDs, Column3: targetIDs,
				Column4: relations, Column5: createdAts,
			}); err != nil {
				return fmt.Errorf("batch upsert note links: %w", err)
			}
		}
	}

	for _, p := range payload.UserNotePreferences {
		ownerID, err := r.GetNoteOwnerID(ctx, p.NoteID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				slog.Error("sync push conflict: GetNoteOwnerID for preference note ID returned ErrNoRows", "pref_note_id", p.NoteID, "user_id", userID, "error", err)
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
				slog.Error("sync push conflict: preference note not owned and share not found/valid", "pref_note_id", p.NoteID, "owner_id", ownerID, "user_id", userID, "error", shareErr)
				return ErrSyncConflict
			}
		}
		_, err = r.UpsertUserNotePreference(ctx, fromUserNotePreferencePayload(p))
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				slog.Error("sync push conflict: UpsertUserNotePreference returned ErrNoRows", "pref_note_id", p.NoteID, "user_id", userID, "error", err)
				return ErrSyncConflict
			}
			return err
		}
	}

	if tx != nil {
		startCommit := time.Now()
		if err := tx.Commit(ctx); err != nil {
			slog.Error("PUSH FAIL: tx.Commit", "elapsed", time.Since(startCommit), "error", err)
			return err
		}
		slog.Info("PUSH TX COMMIT", "elapsed", time.Since(startCommit))
	}

	slog.Info("PUSH DONE", "total", time.Since(startTotal))
	return nil
}

func (s *service) canEditNote(ctx context.Context, r Repository, noteID pgtype.UUID, userID pgtype.UUID, editableNotes map[pgtype.UUID]bool, isClientDelete bool) (bool, error) {
	if canEdit, exists := editableNotes[noteID]; exists {
		return canEdit, nil
	}
	meta, err := r.GetNoteMeta(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: noteID, UserID: userID,
			})
			if shareErr != nil {
				if errors.Is(shareErr, pgx.ErrNoRows) {
					return false, nil
				}
				return false, shareErr
			}
			canEdit := share.Permission == "edit"
			editableNotes[noteID] = canEdit
			return canEdit, nil
		}
		return false, err
	}
	
	if meta.DeletedAt.Valid && !isClientDelete {
		return false, ErrNoteDeleted
	}
	
	ownerID := meta.UserID
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

// UserNotePreferencePayload is the wire shape of a user note preference
// in the sync payload. It uses string for Filters instead of []byte to
// avoid base64 encoding issues with the sqlcgen type.
type UserNotePreferencePayload struct {
	UserID        pgtype.UUID        `json:"user_id"`
	NoteID        pgtype.UUID        `json:"note_id"`
	HideCompleted bool               `json:"hide_completed"`
	Filters       string             `json:"filters"`
	Favorite      bool               `json:"favorite"`
	Archived      bool               `json:"archived"`
	CreatedAt     pgtype.Timestamptz `json:"created_at"`
	UpdatedAt     pgtype.Timestamptz `json:"updated_at"`
}

func toUserNotePreferencePayload(p sqlcgen.UserNotePreference) UserNotePreferencePayload {
	return UserNotePreferencePayload{
		UserID:        p.UserID,
		NoteID:        p.NoteID,
		HideCompleted: p.HideCompleted,
		Filters:       string(p.Filters),
		Favorite:      p.Favorite,
		Archived:      p.Archived,
		CreatedAt:     p.CreatedAt,
		UpdatedAt:     p.UpdatedAt,
	}
}

func fromUserNotePreferencePayload(p UserNotePreferencePayload) sqlcgen.UpsertUserNotePreferenceParams {
	return sqlcgen.UpsertUserNotePreferenceParams{
		UserID:        p.UserID,
		NoteID:        p.NoteID,
		HideCompleted: p.HideCompleted,
		Filters:       []byte(p.Filters),
		Favorite:      p.Favorite,
		Archived:      p.Archived,
		CreatedAt:     p.CreatedAt,
	}
}

