package sync

import (
	"context"
	"errors"
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

var ErrSyncConflict = errors.New("sync conflict")

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

	if s.pool != nil {
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

	// Track note IDs the authenticated user can edit (owned or shared with edit).
	editableNotes := make(map[pgtype.UUID]bool)

	for _, n := range payload.Notes {
		canEdit, err := s.canEditNote(ctx, r, n.ID, userID, editableNotes)
		if err != nil {
			slog.Error("sync push conflict: note permission check failed", "note_id", n.ID, "user_id", userID, "note_owner_id", n.UserID, "error", err)
			return ErrSyncConflict
		}
		if !canEdit && n.UserID == userID {
			canEdit = true
			editableNotes[n.ID] = true
		}
		if !canEdit {
			share, shareErr := s.repo.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
				NoteID: n.ID, UserID: userID,
			})
			if shareErr == nil && share.Permission == "view" {
				continue
			}
			slog.Error("sync push conflict: note edit permission denied", "note_id", n.ID, "user_id", userID, "note_owner_id", n.UserID)
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
			Content:         "", // Derived by projection (ProjectNoteContentFromYDoc)
			EmbeddingStatus: embStatus,
			CollapseImages:  n.CollapseImages,
			CreatedAt:       n.CreatedAt,
			DeletedAt:       n.DeletedAt,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				slog.Error("sync push conflict: UpsertNote returned ErrNoRows", "note_id", noteID, "user_id", upsertUserID, "error", err)
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
				slog.Error("sync push conflict: UpsertContext returned ErrNoRows", "context_id", c.ID, "error", err)
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
				slog.Error("sync push conflict: UpsertTag returned ErrNoRows", "tag_id", t.ID, "error", err)
				return ErrSyncConflict
			}
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

	for _, ys := range payload.NoteYjsStates {
		noteUUID, err := parseUUIDStr(ys.NoteID)
		if err != nil {
			slog.Error("sync push: invalid note UUID in Yjs state", "note_id", ys.NoteID, "error", err)
			return err
		}

		canEdit, err := s.canEditNote(ctx, r, noteUUID, userID, editableNotes)
		if err != nil {
			slog.Error("sync push: Yjs state permission check failed", "note_id", ys.NoteID, "user_id", userID, "error", err)
			return ErrSyncConflict
		}
		if !canEdit {
			slog.Error("sync push: Yjs state for non-editable note", "note_id", ys.NoteID, "user_id", userID)
			return ErrSyncConflict
		}

		// If there's an active WS room, skip — WS is canonical.
		if s.roomMgr.HasActiveRoom(ys.NoteID) {
			slog.Warn("sync push: skipping Yjs state for note with active WS room", "note_id", ys.NoteID)
			continue
		}

		// No active room — apply via YDocService (merge + persistence)
		if s.ydoc != nil {
			if err := s.ydoc.ApplyNodeMutation(ctx, ys.NoteID, ys.State); err != nil {
				slog.Error("sync push: ApplyNodeMutation failed", "note_id", ys.NoteID, "error", err)
				return err
			}
			if err := s.ydoc.FlushUpdates(ctx, ys.NoteID); err != nil {
				slog.Error("sync push: FlushUpdates failed", "note_id", ys.NoteID, "error", err)
				return err
			}
			continue
		}

		// No YDoc service - direct upsert (legacy/fallback)
		if err := r.UpsertNoteYjsState(ctx, sqlcgen.UpsertNoteYjsStateParams{
			NoteID:    noteUUID,
			State:     ys.State,
			UpdatedAt: pgtype.Timestamptz{Time: ys.UpdatedAt, Valid: true},
		}); err != nil {
			slog.Error("sync push: upsert Yjs state failed", "note_id", ys.NoteID, "error", err)
			return err
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

