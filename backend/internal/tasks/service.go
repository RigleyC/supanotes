package tasks

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"strings"
	"time"
)

var (
	ErrTaskNotFound    = errors.New("task not found")
	ErrHashMismatch    = errors.New("operation payload hash mismatch")
	ErrScheduleChanged = errors.New("SCHEDULE_CHANGED")
	ErrTaskDeleted     = errors.New("TASK_DELETED")
	ErrInvalidMutation = errors.New("invalid task mutation")
)

type Service struct{ repo Repository }

func NewService(r Repository) *Service { return &Service{repo: r} }
func (s *Service) Bootstrap(c context.Context, u pgtype.UUID) (BootstrapResult, error) {
	var out BootstrapResult
	err := s.repo.WithTx(c, func(r Repository) error {
		rows, e := r.ListTasks(c, u)
		if e != nil {
			return e
		}
		out.Tasks = make([]Task, 0, len(rows))
		for _, x := range rows {
			out.Tasks = append(out.Tasks, taskFromFields(x.ID, x.OwnerUserID, x.Title, x.DueDate, x.HasTime, x.RecurrenceRule, x.Reminder, x.Completions, x.IsCompleted, x.LastCompletedAt, x.Revision, x.ScheduleGeneration, x.CreatedAt, x.UpdatedAt, x.DeletedAt))
		}
		out.Watermark, e = r.Watermark(c, u)
		return e
	})
	return out, err
}
func (s *Service) Get(c context.Context, id, u pgtype.UUID) (Task, error) {
	x, e := s.repo.GetTask(c, id, u)
	if errors.Is(e, pgx.ErrNoRows) || x.DeletedAt.Valid {
		return Task{}, ErrTaskNotFound
	}
	if e != nil {
		return Task{}, e
	}
	return taskFromFields(x.ID, x.OwnerUserID, x.Title, x.DueDate, x.HasTime, x.RecurrenceRule, x.Reminder, x.Completions, x.IsCompleted, x.LastCompletedAt, x.Revision, x.ScheduleGeneration, x.CreatedAt, x.UpdatedAt, x.DeletedAt), nil
}
func (s *Service) ApplyMutation(c context.Context, u, id pgtype.UUID, m Mutation) (MutationResult, error) {
	var out MutationResult
	e := s.repo.WithTx(c, func(r Repository) error { var e error; out, e = apply(c, r, u, id, m); return e })
	return out, e
}
func apply(c context.Context, r Repository, u, id pgtype.UUID, m Mutation) (MutationResult, error) {
	op, e := uuid.Parse(m.OperationID)
	if e != nil || m.Kind == "" || len(m.Payload) == 0 {
		return MutationResult{}, ErrInvalidMutation
	}
	d := sha256.Sum256(m.Payload)
	hash := hex.EncodeToString(d[:])
	operationID := pgtype.UUID{Bytes: op, Valid: true}
	old, e := r.GetOperation(c, operationID)
	if e == nil {
		if old.PayloadHash != hash {
			return MutationResult{}, ErrHashMismatch
		}
		var out MutationResult
		e = json.Unmarshal(old.ResponseJson, &out)
		return out, e
	}
	if !errors.Is(e, pgx.ErrNoRows) {
		return MutationResult{}, e
	}
	row, e := r.LockTask(c, id, u)
	if errors.Is(e, pgx.ErrNoRows) {
		if m.Kind != "create" && m.Kind != "upsert" {
			return MutationResult{}, ErrTaskNotFound
		}
		var create struct {
			Title string `json:"title"`
		}
		if json.Unmarshal(m.Payload, &create) != nil || strings.TrimSpace(create.Title) == "" {
			return MutationResult{}, ErrInvalidMutation
		}
		row, e = r.InsertTask(c, sqlcgen.InsertTaskParams{ID: id, OwnerUserID: u, Title: strings.TrimSpace(create.Title), Completions: []byte(`{}`), ScheduleGeneration: m.ScheduleGeneration})
	}
	if e != nil {
		return MutationResult{}, e
	}
	if row.DeletedAt.Valid {
		return MutationResult{}, ErrTaskDeleted
	}
	if m.ScheduleGeneration != 0 && m.ScheduleGeneration != row.ScheduleGeneration {
		return MutationResult{}, ErrScheduleChanged
	}
	if m.ObservedRevision > row.Revision {
		return MutationResult{}, ErrScheduleChanged
	}
	var p struct {
		Title          *string                    `json:"title"`
		Completions    map[string]json.RawMessage `json:"completions"`
		IsCompleted    *bool                      `json:"isCompleted"`
		DueDate        *string                    `json:"dueDate"`
		RecurrenceRule *string                    `json:"recurrenceRule"`
		Reminder       *string                    `json:"reminder"`
	}
	if json.Unmarshal(m.Payload, &p) != nil {
		return MutationResult{}, ErrInvalidMutation
	}
	title := row.Title
	if p.Title != nil {
		title = strings.TrimSpace(*p.Title)
		if title == "" || len(title) > 500 {
			return MutationResult{}, ErrInvalidMutation
		}
	}
	gen := row.ScheduleGeneration
	if p.DueDate != nil || p.RecurrenceRule != nil || p.Reminder != nil {
		gen++
	}
	comp := row.Completions
	if len(comp) == 0 {
		comp = []byte(`{}`)
	}
	if p.Completions != nil {
		v := map[string]json.RawMessage{}
		if json.Unmarshal(comp, &v) != nil {
			return MutationResult{}, ErrInvalidMutation
		}
		for k, x := range p.Completions {
			v[k] = x
		}
		comp, _ = json.Marshal(v)
	}
	done := row.IsCompleted
	if p.IsCompleted != nil {
		done = *p.IsCompleted
	}
	deleted := row.DeletedAt
	kind := "task_changed"
	if m.Kind == "delete" {
		deleted = pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}
		kind = "task_deleted"
	}
	x, e := r.UpdateTask(c, sqlcgen.UpdateTaskParams{ID: id, OwnerUserID: u, Title: title, DueDate: row.DueDate, HasTime: row.HasTime, RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder, Completions: comp, IsCompleted: done, LastCompletedAt: row.LastCompletedAt, ScheduleGeneration: gen, DeletedAt: deleted})
	if e != nil {
		return MutationResult{}, e
	}
	t := taskFromFields(x.ID, x.OwnerUserID, x.Title, x.DueDate, x.HasTime, x.RecurrenceRule, x.Reminder, x.Completions, x.IsCompleted, x.LastCompletedAt, x.Revision, x.ScheduleGeneration, x.CreatedAt, x.UpdatedAt, x.DeletedAt)
	out := MutationResult{OperationID: m.OperationID, Revision: x.Revision, Task: t}
	b, _ := json.Marshal(out)
	if e = r.InsertOperation(c, sqlcgen.InsertTaskOperationParams{TaskID: id, OperationID: operationID, PayloadHash: hash, ResponseJson: b}); e != nil {
		return MutationResult{}, e
	}
	if e = r.InsertChange(c, sqlcgen.InsertTaskSyncChangeParams{TargetUserID: u, Kind: kind, TaskID: id, Revision: pgtype.Int8{Int64: x.Revision, Valid: true}}); e != nil {
		return MutationResult{}, e
	}
	return out, nil
}
func taskFromFields(id, owner pgtype.UUID, title string, due pgtype.Timestamp, has bool, rec, rem pgtype.Text, comp []byte, done bool, last pgtype.Timestamptz, rev, gen int64, created, updated, deleted pgtype.Timestamptz) Task {
	if len(comp) == 0 {
		comp = []byte(`{}`)
	}
	return Task{ID: id.String(), OwnerUserID: owner.String(), Title: title, DueDate: formatDate(due), HasTime: has, RecurrenceRule: textPtr(rec), Reminder: textPtr(rem), Completions: json.RawMessage(comp), IsCompleted: done, LastCompletedAt: formatTimestamp(last), Revision: rev, ScheduleGeneration: gen, CreatedAt: created.Time.UTC().Format(time.RFC3339Nano), UpdatedAt: updated.Time.UTC().Format(time.RFC3339Nano), DeletedAt: formatTimestamp(deleted)}
}
func textPtr(v pgtype.Text) *string {
	if !v.Valid {
		return nil
	}
	return &v.String
}
