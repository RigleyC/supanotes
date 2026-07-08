package notes

import (
	"context"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/sync"
)

var (
	ErrNoteNotFound = errors.New("note not found")
	ErrEmptyNote    = errors.New("empty note")
)

type Service struct {
	repo       Repository
	pool       *pgxpool.Pool
	noteSyncer sync.NoteStateSyncer
}

func NewService(repo Repository, pool *pgxpool.Pool, noteSyncer sync.NoteStateSyncer) *Service {
	return &Service{repo: repo, pool: pool, noteSyncer: noteSyncer}
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

	if err = s.overwriteNoteNodes(ctx, userID, note.ID, content); err != nil {
		return sqlcgen.Note{}, err
	}

	if s.noteSyncer != nil {
		if err := s.noteSyncer.SyncNoteToYjs(ctx, note.ID); err != nil {
			log.Printf("ERROR: yjs sync after create note %v: %v", note.ID, err)
		}
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
	var contentChanged bool
	if content != nil {
		arg.Content = pgtype.Text{String: *content, Valid: true}
		arg.EmbeddingStatus = pgtype.Text{String: "pending", Valid: true}

		if err := s.overwriteNoteNodes(ctx, userID, id, *content); err != nil {
			return sqlcgen.Note{}, err
		}
		contentChanged = true
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

	if contentChanged && s.noteSyncer != nil {
		if err := s.noteSyncer.SyncNoteToYjs(ctx, note.ID); err != nil {
			log.Printf("ERROR: yjs sync after update note %v: %v", note.ID, err)
		}
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

func (s *Service) AppendToNoteContent(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID, content string) (sqlcgen.Note, error) {
	// Verify note exists and belongs to user
	_, err := s.GetNoteByID(ctx, noteID, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}

	currentNodes, err := s.repo.GetNodesByNoteId(ctx, noteID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	startPos := len(currentNodes)

	nodes := ParseMarkdownToNodes(content)
	for i, node := range nodes {
		_, err := s.repo.InsertNode(ctx, sqlcgen.InsertNodeParams{
			ID:       node.ID,
			NoteID:   noteID,
			Position: float64(startPos + i),
			Type:     node.Type,
			Data:     node.Data,
		})
		if err != nil {
			return sqlcgen.Note{}, fmt.Errorf("append to note: insert node: %w", err)
		}

		if node.IsTask {
			_, err = s.repo.CreateTask(ctx, sqlcgen.CreateTaskParams{
				NoteID:     noteID,
				UserID:     userID,
				Title:      node.Text,
				DueDate:    pgtype.Date{Valid: false},
				Recurrence: pgtype.Text{Valid: false},
				Position:   float64(startPos + i),
				NodeID:     node.ID,
			})
			if err != nil {
				return sqlcgen.Note{}, fmt.Errorf("append to note: create task: %w", err)
			}
		}
	}

	note, err := s.repo.AppendToNoteContent(ctx, sqlcgen.AppendToNoteContentParams{
		ID:      noteID,
		UserID:  userID,
		Content: content,
	})
	if err != nil {
		return sqlcgen.Note{}, err
	}

	if s.noteSyncer != nil {
		if err := s.noteSyncer.SyncNoteToYjs(ctx, noteID); err != nil {
			log.Printf("ERROR: yjs sync after append note %v: %v", noteID, err)
		}
	}

	return note, nil
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

func (s *Service) overwriteNoteNodes(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID, content string) error {
	// 1. Fetch current nodes to find task nodes to delete
	currentNodes, err := s.repo.GetNodesByNoteId(ctx, noteID)
	if err == nil {
		for _, node := range currentNodes {
			if node.Type == "task" {
				_ = s.repo.DeleteTaskByNodeID(ctx, sqlcgen.DeleteTaskByNodeIDParams{
					NodeID: node.ID,
					UserID: userID,
				})
			}
		}
	}

	// 2. Delete all existing nodes
	err = s.repo.DeleteNodesByNoteID(ctx, noteID)
	if err != nil {
		return err
	}

	// 3. Parse and insert new nodes
	nodes := ParseMarkdownToNodes(content)
	for i, node := range nodes {
		_, err := s.repo.InsertNode(ctx, sqlcgen.InsertNodeParams{
			ID:       node.ID,
			NoteID:   noteID,
			Position: float64(i),
			Type:     node.Type,
			Data:     node.Data,
		})
		if err != nil {
			return fmt.Errorf("overwrite node: insert: %w", err)
		}

		if node.IsTask {
			_, err = s.repo.CreateTask(ctx, sqlcgen.CreateTaskParams{
				NoteID:     noteID,
				UserID:     userID,
				Title:      node.Text,
				DueDate:    pgtype.Date{Valid: false},
				Recurrence: pgtype.Text{Valid: false},
				Position:   float64(i),
				NodeID:     node.ID,
			})
			if err != nil {
				return fmt.Errorf("overwrite node: create task: %w", err)
			}
		}
	}

	return nil
}

func (s *Service) GetNoteMarkdownByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (string, error) {
	_, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return "", err
	}

	nodes, err := s.repo.GetNodesByNoteId(ctx, id)
	if err != nil {
		return "", err
	}

	tasks, err := s.repo.GetTasksByNoteID(ctx, userID, id)
	if err != nil {
		return "", err
	}

	taskMap := make(map[pgtype.UUID]sqlcgen.Task)
	for _, t := range tasks {
		if t.NodeID.Valid {
			taskMap[t.NodeID] = t
		}
	}

	return RenderNoteToMarkdown(nodes, taskMap), nil
}
