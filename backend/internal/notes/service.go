package notes

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

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
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func isEmptyRegularNote(title *string, content string) bool {
	return (title == nil || strings.TrimSpace(*title) == "") && strings.TrimSpace(content) == ""
}

func (s *Service) CreateNote(ctx context.Context, userID pgtype.UUID, title *string, content string, contextID *pgtype.UUID, favorite, archived bool) (sqlcgen.Note, error) {
	if isEmptyRegularNote(title, content) {
		return sqlcgen.Note{}, ErrEmptyNote
	}
	arg := sqlcgen.CreateNoteParams{
		UserID:          userID,
		Content:         content,
		IsInbox:         false,
		Favorite:        favorite,
		Archived:        archived,
		EmbeddingStatus: "pending",
	}
	if title != nil {
		arg.Title = pgtype.Text{String: *title, Valid: true}
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

func (s *Service) UpdateNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID, title *string, content *string, contextID *pgtype.UUID, favorite *bool, archived *bool) (sqlcgen.Note, error) {
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
	if title != nil {
		arg.Title = pgtype.Text{String: *title, Valid: true}
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

func (s *Service) ApplyOrganization(ctx context.Context, userID pgtype.UUID, items []PlanOrganizationItem) error {
	inbox, err := s.GetInboxNote(ctx, userID)
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

	for _, item := range items {
		if !item.Accepted {
			continue
		}

		fullSnippet := item.OriginalSnippet
		parts := strings.Split(item.ItemID, "-")
		if len(parts) >= 2 {
			var idx int
			_, scanErr := fmt.Sscanf(parts[len(parts)-1], "%d", &idx)
			if scanErr == nil && idx >= 0 && idx < len(lines) {
				candidate := strings.TrimSpace(lines[idx])
				prefix := strings.TrimSuffix(item.OriginalSnippet, "...")
				if strings.HasPrefix(candidate, prefix) {
					fullSnippet = candidate
				}
			}
		}

		switch item.DestinationType {
		case DestNewNote:
			if _, err := s.CreateNote(ctx, userID, item.DestinationTitle, fullSnippet, nil, false, false); err != nil {
				return fmt.Errorf("create note: %w", err)
			}
		case DestExistingNote:
			if item.DestinationNoteID == nil {
				continue
			}
			noteID, err := uid.UUIDFromString(*item.DestinationNoteID)
			if err != nil {
				return fmt.Errorf("invalid destination note id: %w", err)
			}
			if _, err := s.AppendToNoteContent(ctx, userID, noteID, fullSnippet); err != nil {
				return fmt.Errorf("append to note: %w", err)
			}
		case DestKeep:
		}
	}

	var keptLines []string
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		itemID := fmt.Sprintf("%s-%d", noteIDStr, i)
		reqItem, isOutgoing := outgoing[itemID]
		if !isOutgoing || reqItem.DestinationType == DestKeep {
			keptLines = append(keptLines, trimmed)
		}
	}
	newContent := strings.Join(keptLines, "\n\n")
	_, err = s.SetInboxContent(ctx, userID, newContent)
	return err
}
