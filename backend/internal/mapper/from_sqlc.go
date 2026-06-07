package mapper

import (
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
)

func NoteFromSQLC(n sqlcgen.Note) dto.NoteResponse {
	var contextID *string
	if n.ContextID.Valid {
		s := UUID(n.ContextID)
		contextID = &s
	}
	var title *string
	if n.Title.Valid {
		s := n.Title.String
		title = &s
	}
	var excerpt *string
	if n.Excerpt.Valid {
		s := n.Excerpt.String
		excerpt = &s
	}
	return dto.NoteResponse{
		ID:        UUID(n.ID),
		ContextID: contextID,
		Title:     title,
		Content:   n.Content,
		Excerpt:   excerpt,
		IsInbox:   n.IsInbox,
		Favorite:  n.Favorite,
		Archived:  n.Archived,
		CreatedAt: Time(n.CreatedAt),
		UpdatedAt: Time(n.UpdatedAt),
	}
}

func TaskFromSQLC(t sqlcgen.Task) dto.TaskResponse {
	var recurrence *string
	if t.Recurrence.Valid {
		s := t.Recurrence.String
		recurrence = &s
	}
	return dto.TaskResponse{
		ID:         UUID(t.ID),
		NoteID:     UUID(t.NoteID),
		Title:      t.Title,
		Status:     t.Status,
		DueDate:    OptTime(t.DueDate),
		Recurrence: recurrence,
		Position:   int(t.Position),
		CreatedAt:  Time(t.CreatedAt),
		UpdatedAt:  Time(t.UpdatedAt),
	}
}

func ContextFromSQLC(c sqlcgen.Context) dto.ContextResponse {
	return dto.ContextResponse{
		ID:        UUID(c.ID),
		Slug:      c.Slug,
		Name:      c.Name,
		CreatedAt: Time(c.CreatedAt),
		UpdatedAt: Time(c.UpdatedAt),
	}
}

func TagFromSQLC(t sqlcgen.Tag) dto.TagResponse {
	return dto.TagResponse{
		ID:        UUID(t.ID),
		Name:      t.Name,
		CreatedAt: Time(t.CreatedAt),
	}
}

func MemoryFromSQLC(m sqlcgen.Memory) dto.MemoryResponse {
	return dto.MemoryResponse{
		ID:        UUID(m.ID),
		Content:   m.Content,
		CreatedAt: Time(m.CreatedAt),
		UpdatedAt: Time(m.UpdatedAt),
	}
}

func MessageFromSQLC(m sqlcgen.Message) dto.MessageResponse {
	return dto.MessageResponse{
		ID:        UUID(m.ID),
		SessionID: UUID(m.SessionID),
		Role:      m.Role,
		Content:   m.Content,
		CreatedAt: Time(m.CreatedAt),
	}
}

func SyncNoteFromSQLC(n sqlcgen.Note) dto.SyncNote {
	var contextID *string
	if n.ContextID.Valid {
		s := UUID(n.ContextID)
		contextID = &s
	}
	var title *string
	if n.Title.Valid {
		s := n.Title.String
		title = &s
	}
	var excerpt *string
	if n.Excerpt.Valid {
		s := n.Excerpt.String
		excerpt = &s
	}
	return dto.SyncNote{
		ID:              UUID(n.ID),
		UserID:          UUID(n.UserID),
		ContextID:       contextID,
		Title:           title,
		Content:         n.Content,
		Excerpt:         excerpt,
		IsInbox:         n.IsInbox,
		Favorite:        n.Favorite,
		Archived:        n.Archived,
		EmbeddingStatus: n.EmbeddingStatus,
		CreatedAt:       Time(n.CreatedAt),
		UpdatedAt:       Time(n.UpdatedAt),
		DeletedAt:       OptTime(n.DeletedAt),
	}
}

func SyncTaskFromSQLC(t sqlcgen.Task) dto.SyncTask {
	var recurrence *string
	if t.Recurrence.Valid {
		s := t.Recurrence.String
		recurrence = &s
	}
	return dto.SyncTask{
		ID:         UUID(t.ID),
		NoteID:     UUID(t.NoteID),
		UserID:     UUID(t.UserID),
		Title:      t.Title,
		Status:     t.Status,
		DueDate:    OptTime(t.DueDate),
		Recurrence: recurrence,
		Position:   int(t.Position),
		CreatedAt:  Time(t.CreatedAt),
		UpdatedAt:  Time(t.UpdatedAt),
		DeletedAt:  OptTime(t.DeletedAt),
	}
}

func SyncContextFromSQLC(c sqlcgen.Context) dto.SyncContext {
	return dto.SyncContext{
		ID:        UUID(c.ID),
		UserID:    UUID(c.UserID),
		Slug:      c.Slug,
		Name:      c.Name,
		CreatedAt: Time(c.CreatedAt),
		UpdatedAt: Time(c.UpdatedAt),
	}
}

func SyncTagFromSQLC(t sqlcgen.Tag) dto.SyncTag {
	return dto.SyncTag{
		ID:        UUID(t.ID),
		UserID:    UUID(t.UserID),
		Name:      t.Name,
		CreatedAt: Time(t.CreatedAt),
	}
}

func SyncTaskCompletionFromSQLC(tc sqlcgen.TaskCompletion) dto.SyncTaskCompletion {
	return dto.SyncTaskCompletion{
		ID:          UUID(tc.ID),
		TaskID:      UUID(tc.TaskID),
		CompletedAt: Time(tc.CompletedAt),
		Status:      tc.Status,
	}
}
