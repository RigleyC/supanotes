package notes

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrNoteNotFound = errors.New("note not found")
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

func (s *Service) CreateNote(ctx context.Context, userID pgtype.UUID, content string, contextID *pgtype.UUID, collapseImages bool) (sqlcgen.Note, error) {
	if isEmptyRegularNote(content) {
		return sqlcgen.Note{}, ErrEmptyNote
	}
	arg := sqlcgen.CreateNoteParams{
		UserID:          userID,
		Content:         content,
		EmbeddingStatus: "pending",
		CollapseImages:  collapseImages,
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	note, err := s.repo.CreateNote(ctx, arg)
	if err != nil {
		return sqlcgen.Note{}, err
	}

	return note, nil
}

func (s *Service) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
	note, err := s.repo.GetNoteByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.GetNoteByIDRow{}, ErrNoteNotFound
		}
		return sqlcgen.GetNoteByIDRow{}, err
	}
	return note, nil
}

func (s *Service) UpdateNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID, content *string, contextID *pgtype.UUID, collapseImages *bool) (sqlcgen.Note, error) {
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
	if collapseImages != nil {
		arg.CollapseImages = pgtype.Bool{Bool: *collapseImages, Valid: true}
	}

	note, err := s.repo.UpdateNote(ctx, arg)
	if err != nil {
		return sqlcgen.Note{}, err
	}

	return note, nil
}

func (s *Service) DeleteNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID) error {
	return s.repo.DeleteNote(ctx, id, userID)
}

func (s *Service) GetNotes(ctx context.Context, userID pgtype.UUID, contextID *pgtype.UUID, favorite *bool, limit int32, cursorUpdatedAt *time.Time, cursorID *pgtype.UUID) ([]sqlcgen.GetNotesRow, error) {
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

func (s *Service) GetNoteMarkdownByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (string, error) {
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return "", err
	}

	return note.Content, nil
}
