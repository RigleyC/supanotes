package shoppinglist

import (
	"context"
	"encoding/json"
	"errors"
	"strings"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
)

const ShoppingListTitle = "Lista de compras"

var (
	ErrEmptyItem         = errors.New("shopping list item is empty")
	ErrShoppingNotFound  = errors.New("shopping list note not found")
	ErrShoppingAmbiguous = errors.New("multiple shopping list notes found")
)

type Service struct {
	notes *notes.Service
	ops   noteoperations.DocumentService
}

func NewService(notesSvc *notes.Service, opsSvc noteoperations.DocumentService) *Service {
	return &Service{notes: notesSvc, ops: opsSvc}
}

func (s *Service) AddItem(ctx context.Context, userID pgtype.UUID, item string) error {
	item = strings.TrimSpace(item)
	if item == "" {
		return ErrEmptyItem
	}

	noteID, err := s.findShoppingList(ctx, userID)
	if err != nil {
		return err
	}
	doc, err := s.ops.GetDocument(ctx, noteID, userID)
	if err != nil {
		return err
	}

	var current noteoperations.Document
	if err := json.Unmarshal(doc.Document, &current); err != nil {
		return err
	}
	var after string
	if len(current.Blocks) > 0 {
		after = current.Blocks[len(current.Blocks)-1].ID
	}
	blockID := uuid.New()
	opID := uuid.New()
	payload, err := json.Marshal(noteoperations.CreateBlockPayload{
		ID: blockID.String(), Type: string(noteoperations.BlockTask),
		Delta: []delta.Op{{Insert: []rune(item)}}, Metadata: map[string]any{}, AfterBlockID: after,
	})
	if err != nil {
		return err
	}
	_, err = s.ops.SyncOperations(ctx, noteID, userID, noteoperations.SyncRequest{
		KnownRevision: doc.Revision,
		ClientID:      "shopping-list-command",
		Operations: []noteoperations.OperationRequest{{
			OperationID: opID.String(), BaseRevision: doc.Revision,
			Kind: string(noteoperations.KindCreateBlock), BlockID: ptr(blockID.String()), Payload: payload,
		}},
	})
	return err
}

func (s *Service) findShoppingList(ctx context.Context, userID pgtype.UUID) (pgtype.UUID, error) {
	items, err := s.notes.GetNotes(ctx, userID, nil, 100, nil, nil)
	if err != nil {
		return pgtype.UUID{}, err
	}
	var matches []pgtype.UUID
	for _, item := range items {
		if !item.Archived && strings.EqualFold(strings.TrimSpace(item.Title), ShoppingListTitle) {
			matches = append(matches, item.ID)
		}
	}
	if len(matches) == 0 {
		return pgtype.UUID{}, ErrShoppingNotFound
	}
	if len(matches) > 1 {
		return pgtype.UUID{}, ErrShoppingAmbiguous
	}
	return matches[0], nil
}

func ptr(v string) *string { return &v }
