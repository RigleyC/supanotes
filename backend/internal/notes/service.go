package notes

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var (
	ErrNoteNotFound = errors.New("note not found")
	ErrInboxRule    = errors.New("operation not allowed on inbox note")
	ErrEmptyNote    = errors.New("empty note")
)

type Service struct {
	repo Repository
	pool *pgxpool.Pool
}

func NewService(repo Repository, pool *pgxpool.Pool) *Service {
	return &Service{repo: repo, pool: pool}
}

func isEmptyRegularNote(content string) bool {
	return strings.TrimSpace(content) == ""
}

func (s *Service) CreateNote(ctx context.Context, userID pgtype.UUID, content string, contextID *pgtype.UUID, favorite, archived, hideCompleted bool) (sqlcgen.Note, error) {
	if isEmptyRegularNote(content) {
		return sqlcgen.Note{}, ErrEmptyNote
	}
	arg := sqlcgen.CreateNoteParams{
		UserID:          userID,
		Content:         content,
		IsInbox:         false,
		Favorite:        favorite,
		Archived:        archived,
		EmbeddingStatus: "pending",
		HideCompleted:   hideCompleted,
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	return s.repo.CreateNote(ctx, arg)
}

func (s *Service) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	note, err := s.repo.GetNoteByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Note{}, ErrNoteNotFound
		}
		return sqlcgen.Note{}, err
	}
	return note, nil
}

func (s *Service) UpdateNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID, content *string, contextID *pgtype.UUID, favorite *bool, archived *bool, hideCompleted *bool) (sqlcgen.Note, error) {
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	if note.IsInbox {
		// Inbox note properties should not be easily manipulated (except content).
		if archived != nil && *archived {
			return sqlcgen.Note{}, ErrInboxRule
		}
	}

	arg := sqlcgen.UpdateNoteParams{
		ID:     id,
		UserID: userID,
	}
	if content != nil {
		arg.Content = pgtype.Text{String: *content, Valid: true}
		arg.EmbeddingStatus = pgtype.Text{String: "pending", Valid: true}
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	if favorite != nil {
		arg.Favorite = pgtype.Bool{Bool: *favorite, Valid: true}
	}
	if archived != nil {
		arg.Archived = pgtype.Bool{Bool: *archived, Valid: true}
	}
	if hideCompleted != nil {
		arg.HideCompleted = pgtype.Bool{Bool: *hideCompleted, Valid: true}
	}

	return s.repo.UpdateNote(ctx, arg)
}

func (s *Service) DeleteNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID) error {
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return err
	}
	if note.IsInbox {
		return ErrInboxRule
	}
	return s.repo.DeleteNote(ctx, id, userID)
}

func (s *Service) GetNotes(ctx context.Context, userID pgtype.UUID, contextID *pgtype.UUID, favorite *bool, limit int32, cursorUpdatedAt *time.Time, cursorID *pgtype.UUID) ([]sqlcgen.Note, error) {
	arg := sqlcgen.GetNotesParams{
		UserID: userID,
		Limit:  limit,
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	if favorite != nil {
		arg.Favorite = pgtype.Bool{Bool: *favorite, Valid: true}
	}
	if cursorUpdatedAt != nil && cursorID != nil {
		arg.CursorUpdatedAt = pgtype.Timestamptz{Time: *cursorUpdatedAt, Valid: true}
		arg.CursorID = *cursorID
	}

	return s.repo.GetNotes(ctx, arg)
}

func (s *Service) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	note, err := s.repo.GetInboxNote(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Note{}, ErrNoteNotFound
		}
		return sqlcgen.Note{}, err
	}
	return note, nil
}

func (s *Service) SetInboxContent(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Note, error) {
	note, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	return s.repo.SetInboxContent(ctx, sqlcgen.SetInboxContentParams{
		ID:      note.ID,
		UserID:  userID,
		Content: content,
	})
}

func (s *Service) AppendToNoteContent(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID, content string) (sqlcgen.Note, error) {
	// Verify note exists and belongs to user
	_, err := s.GetNoteByID(ctx, noteID, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	return s.repo.AppendToNoteContent(ctx, sqlcgen.AppendToNoteContentParams{
		ID:      noteID,
		UserID:  userID,
		Content: content,
	})
}

func (s *Service) AppendToInbox(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Note, error) {
	note, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	return s.repo.AppendToInbox(ctx, sqlcgen.AppendToInboxParams{
		ID:      note.ID,
		UserID:  userID,
		Content: content,
	})
}

const (
	batchCreateNoteSQL = `INSERT INTO notes (user_id, context_id, content, is_inbox, favorite, archived, embedding_status, hide_completed)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id`

	batchAppendToNoteContentSQL = `UPDATE notes
SET content = content || E'\n\n' || $3, updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL AND is_inbox = false
RETURNING id`
)

func (s *Service) ApplyOrganization(ctx context.Context, userID pgtype.UUID, items []PlanOrganizationItem) error {
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

	inbox, err := r.GetInboxNote(ctx, userID)
	if err != nil {
		return err
	}

	noteIDStr := uid.UUIDToString(inbox.ID)
	lines := strings.Split(inbox.Content, "\n\n")

	outgoing := make(map[string]PlanOrganizationItem, len(items))
	for _, item := range items {
		if item.Accepted {
			outgoing[item.ItemID] = item
		}
	}

	type createOp struct {
		content string
	}
	type appendOp struct {
		noteID  pgtype.UUID
		content string
	}

	var (
		creates   []createOp
		appends   []appendOp
		keptLines []string
	)

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		itemID := fmt.Sprintf("%s-%d", noteIDStr, i)
		reqItem, isOutgoing := outgoing[itemID]

		if !isOutgoing {
			keptLines = append(keptLines, trimmed)
			continue
		}

		switch reqItem.DestinationType {
		case DestNewNote:
			content := trimmed
			if reqItem.DestinationTitle != nil && strings.TrimSpace(*reqItem.DestinationTitle) != "" {
				content = fmt.Sprintf("# %s\n\n%s", *reqItem.DestinationTitle, trimmed)
			}
			creates = append(creates, createOp{content: content})
		case DestExistingNote:
			if reqItem.DestinationNoteID != nil {
				noteID, err := uid.UUIDFromString(*reqItem.DestinationNoteID)
				if err == nil {
					if _, err := r.GetNoteByID(ctx, noteID, userID); err != nil {
						return fmt.Errorf("destination note not found: %w", err)
					}
					appends = append(appends, appendOp{noteID: noteID, content: trimmed})
				} else {
					return fmt.Errorf("invalid destination note id: %w", err)
				}
			}
		case DestKeep:
			keptLines = append(keptLines, trimmed)
		}
	}

	newContent := strings.Join(keptLines, "\n\n")

	if len(creates) > 0 || len(appends) > 0 {
		if s.pool != nil {
			var batch pgx.Batch
			for _, op := range creates {
				batch.Queue(batchCreateNoteSQL,
					userID,
					pgtype.UUID{},
					op.content,
					false,
					false,
					false,
					"pending",
					false,
				)
			}
			for _, op := range appends {
				batch.Queue(batchAppendToNoteContentSQL, op.noteID, userID, op.content)
			}

			br := tx.SendBatch(ctx, &batch)

			for range creates {
				var id pgtype.UUID
				if err := br.QueryRow().Scan(&id); err != nil {
					br.Close()
					return fmt.Errorf("batch create note: %w", err)
				}
			}
			for range appends {
				var id pgtype.UUID
				if err := br.QueryRow().Scan(&id); err != nil {
					br.Close()
					return fmt.Errorf("batch append to note: %w", err)
				}
			}
			if err := br.Close(); err != nil {
				return err
			}
		} else {
			for _, op := range creates {
				if _, err := r.CreateNote(ctx, sqlcgen.CreateNoteParams{
					UserID:          userID,
					Content:         op.content,
					IsInbox:         false,
					Favorite:        false,
					Archived:        false,
					EmbeddingStatus: "pending",
					HideCompleted:   false,
				}); err != nil {
					return fmt.Errorf("create note: %w", err)
				}
			}
			for _, op := range appends {
				if _, err := r.AppendToNoteContent(ctx, sqlcgen.AppendToNoteContentParams{
					ID:      op.noteID,
					UserID:  userID,
					Content: op.content,
				}); err != nil {
					return fmt.Errorf("append to note: %w", err)
				}
			}
		}
	}

	if _, err = r.SetInboxContent(ctx, sqlcgen.SetInboxContentParams{
		ID:      inbox.ID,
		UserID:  userID,
		Content: newContent,
	}); err != nil {
		return err
	}

	if tx != nil {
		return tx.Commit(ctx)
	}
	return nil
}

var (
	headerRegex  = regexp.MustCompile(`^#+\s*`)
	listRegex    = regexp.MustCompile(`^[-*]\s*(\[[ xX]\]\s*)?`)
	numListRegex = regexp.MustCompile(`^\d+\.\s*`)
)

func DeriveTitle(content string) string {
	lines := strings.Split(content, "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			clean := headerRegex.ReplaceAllString(trimmed, "")
			clean = listRegex.ReplaceAllString(clean, "")
			clean = numListRegex.ReplaceAllString(clean, "")
			clean = strings.TrimSpace(clean)
			if clean != "" {
				return clean
			}
		}
	}
	return "Sem título"
}
