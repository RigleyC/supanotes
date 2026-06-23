package notes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var (
	ErrNoteNotFound = errors.New("note not found")
	ErrInboxRule    = errors.New("operation not allowed on inbox note")
	ErrEmptyNote    = errors.New("empty note")
)

const (
	DestNewNote      = "new_note"
	DestExistingNote = "existing_note"
	DestKeep         = "keep"
)

type PlanOrganizationItem struct {
	ItemID            string  `json:"item_id"`
	OriginalSnippet   string  `json:"original_snippet"`
	DestinationType   string  `json:"destination_type"`
	DestinationNoteID *string `json:"destination_note_id,omitempty"`
	DestinationTitle  *string `json:"destination_title,omitempty"`
	Accepted          bool    `json:"accepted"`
}

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
		IsInbox:         false,
		EmbeddingStatus: "pending",
		CollapseImages:  collapseImages,
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	return s.repo.CreateNote(ctx, arg)
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
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	if note.IsInbox {
		return sqlcgen.Note{}, ErrInboxRule
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
	if collapseImages != nil {
		arg.CollapseImages = pgtype.Bool{Bool: *collapseImages, Valid: true}
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

func (s *Service) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.GetInboxNoteRow, error) {
	note, err := s.repo.GetInboxNote(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.GetInboxNoteRow{}, ErrNoteNotFound
		}
		return sqlcgen.GetInboxNoteRow{}, err
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
	batchCreateNoteSQL = `INSERT INTO notes (user_id, context_id, content, is_inbox, embedding_status)
VALUES ($1, $2, $3, $4, $5)
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
					"pending",
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
					EmbeddingStatus: "pending",
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

type llmPlanItem struct {
	Snippet     string `json:"snippet"`
	Destination string `json:"destination"`
	Title       string `json:"title,omitempty"`
}

func (s *Service) PlanInboxOrganization(ctx context.Context, userID pgtype.UUID, llmClient llm.Client) ([]PlanOrganizationItem, error) {
	note, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return nil, err
	}

	if strings.TrimSpace(note.Content) == "" {
		return []PlanOrganizationItem{}, nil
	}

	systemPrompt := `Você é um organizador de notas. Analise o conteúdo do inbox abaixo e organize cada item.

O inbox contém várias anotações separadas por linhas em branco. Para cada anotação, decida o destino:
- "new_note": virar uma nova nota → forneça um título descritivo curto
- "keep": permanecer no inbox (anotações vagas, lembretes rápidos, ideas não desenvolvidas)

Responda APENAS com um JSON array válido. Exemplo:
[{"snippet": "primeira anotação", "destination": "new_note", "title": "Título Descritivo"},
 {"snippet": "segunda anotação", "destination": "keep"}]`

	resp, err := llmClient.Complete(ctx, llm.Request{
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: "Aqui está meu inbox:\n\n" + note.Content},
		},
		MaxTokens:   2000,
		Temperature: 0.3,
	})

	var llmItems []llmPlanItem
	if err != nil {
		slog.Error("ai planning failed, falling back to mechanical split", "error", err)
		llmItems = s.fallbackPlan(note.Content)
	} else {
		content := strings.TrimSpace(resp.Content)
		content = strings.TrimPrefix(content, "```json")
		content = strings.TrimPrefix(content, "```")
		content = strings.TrimSpace(content)
		content = strings.TrimSuffix(content, "```")
		content = strings.TrimSpace(content)

		if err := json.Unmarshal([]byte(content), &llmItems); err != nil {
			slog.Error("failed to parse llm plan, falling back to mechanical split", "error", err)
			llmItems = s.fallbackPlan(note.Content)
		}
	}

	items := make([]PlanOrganizationItem, 0, len(llmItems))
	noteIDStr := uid.UUIDToString(note.ID)
	snippetIndex := 0

	for _, li := range llmItems {
		trimmedSnippet := strings.TrimSpace(li.Snippet)
		if trimmedSnippet == "" {
			continue
		}
		itemID := fmt.Sprintf("%s-%d", noteIDStr, snippetIndex)
		snippetIndex++

		displaySnippet := trimmedSnippet
		if len(displaySnippet) > 150 {
			displaySnippet = displaySnippet[:150] + "..."
		}

		item := PlanOrganizationItem{
			ItemID:          itemID,
			OriginalSnippet: displaySnippet,
			DestinationType: li.Destination,
			Accepted:        true,
		}
		if li.Destination == DestNewNote && li.Title != "" {
			item.DestinationTitle = &li.Title
		}
		items = append(items, item)
	}

	return items, nil
}

func (s *Service) fallbackPlan(noteContent string) []llmPlanItem {
	lines := strings.Split(noteContent, "\n\n")
	var items []llmPlanItem
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		items = append(items, llmPlanItem{
			Snippet:     trimmed,
			Destination: DestNewNote,
		})
	}
	if len(items) == 0 {
		trimmed := strings.TrimSpace(noteContent)
		if trimmed != "" {
			items = append(items, llmPlanItem{
				Snippet:     trimmed,
				Destination: DestKeep,
			})
		}
	}
	return items
}
