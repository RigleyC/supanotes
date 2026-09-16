package alexa

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

const (
	alexaIdempotencyResultTTL = 5 * time.Minute
	alexaIdempotencyLeaseTTL  = 30 * time.Second
)

var errRequestIDPayloadMismatch = errors.New("Alexa request ID was reused with another payload")
var errIdempotencyReservationLost = errors.New("Alexa idempotency reservation is no longer owned")

type idempotencyStore interface {
	Acquire(context.Context, string, string, string) (idempotencyDecision, error)
	Complete(context.Context, idempotencyReservation, response) error
}

type idempotencyReservation struct {
	applicationID string
	requestID     string
	ownerToken    string
}

type idempotencyDecision struct {
	reservation idempotencyReservation
	response    *response
	pending     bool
}

// PostgresIdempotencyStore persists Alexa request reservations and responses.
// A pending row is never expired; only its lease can expire, allowing a later
// delivery to recover work after a process crash.
type PostgresIdempotencyStore struct {
	pool      *pgxpool.Pool
	resultTTL time.Duration
	leaseTTL  time.Duration
	now       func() time.Time
}

func NewPostgresIdempotencyStore(pool *pgxpool.Pool) *PostgresIdempotencyStore {
	return &PostgresIdempotencyStore{
		pool:      pool,
		resultTTL: alexaIdempotencyResultTTL,
		leaseTTL:  alexaIdempotencyLeaseTTL,
		now:       time.Now,
	}
}

func (s *PostgresIdempotencyStore) Acquire(
	ctx context.Context,
	applicationID string,
	requestID string,
	fingerprint string,
) (idempotencyDecision, error) {
	if s == nil || s.pool == nil {
		return idempotencyDecision{}, errors.New("Alexa idempotency store is not configured")
	}

	now := s.now()
	ownerToken := uuid.NewString()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return idempotencyDecision{}, err
	}
	defer tx.Rollback(ctx)
	queries := sqlcgen.New(tx)

	if err := queries.DeleteExpiredAlexaRequestIdempotency(ctx); err != nil {
		return idempotencyDecision{}, err
	}

	row, err := queries.InsertAlexaRequestIdempotency(ctx, sqlcgen.InsertAlexaRequestIdempotencyParams{
		ApplicationID: applicationID,
		RequestID:     requestID,
		Fingerprint:   fingerprint,
		OwnerToken:    ownerToken,
		LeaseUntil:    timestamptz(now.Add(s.leaseTTL)),
	})
	if err == nil {
		if err := tx.Commit(ctx); err != nil {
			return idempotencyDecision{}, err
		}
		return idempotencyDecision{reservation: idempotencyReservation{
			applicationID: applicationID,
			requestID:     requestID,
			ownerToken:    ownerToken,
		}}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return idempotencyDecision{}, err
	}

	row, err = queries.GetAlexaRequestIdempotencyForUpdate(ctx, sqlcgen.GetAlexaRequestIdempotencyForUpdateParams{
		ApplicationID: applicationID,
		RequestID:     requestID,
	})
	if err != nil {
		return idempotencyDecision{}, err
	}
	if row.Fingerprint != fingerprint {
		return idempotencyDecision{}, errRequestIDPayloadMismatch
	}

	if row.Status == "completed" && row.ExpiresAt.Valid && now.Before(row.ExpiresAt.Time) {
		var replay response
		if err := json.Unmarshal(row.ResponseJson, &replay); err != nil {
			return idempotencyDecision{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return idempotencyDecision{}, err
		}
		return idempotencyDecision{response: &replay}, nil
	}

	if row.Status == "completed" {
		if _, err := queries.ReuseExpiredAlexaRequestIdempotency(ctx, sqlcgen.ReuseExpiredAlexaRequestIdempotencyParams{
			ApplicationID: applicationID,
			RequestID:     requestID,
			Fingerprint:   fingerprint,
			OwnerToken:    ownerToken,
			LeaseUntil:    timestamptz(now.Add(s.leaseTTL)),
		}); err != nil {
			return idempotencyDecision{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return idempotencyDecision{}, err
		}
		return idempotencyDecision{reservation: idempotencyReservation{
			applicationID: applicationID,
			requestID:     requestID,
			ownerToken:    ownerToken,
		}}, nil
	}

	if row.Status != "pending" {
		return idempotencyDecision{}, errors.New("invalid Alexa idempotency status")
	}
	if row.LeaseUntil.Time.After(now) {
		if err := tx.Commit(ctx); err != nil {
			return idempotencyDecision{}, err
		}
		return idempotencyDecision{pending: true}, nil
	}

	if _, err := queries.TakeOverAlexaRequestIdempotency(ctx, sqlcgen.TakeOverAlexaRequestIdempotencyParams{
		ApplicationID: applicationID,
		RequestID:     requestID,
		OwnerToken:    ownerToken,
		LeaseUntil:    timestamptz(now.Add(s.leaseTTL)),
	}); err != nil {
		return idempotencyDecision{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return idempotencyDecision{}, err
	}
	return idempotencyDecision{reservation: idempotencyReservation{
		applicationID: applicationID,
		requestID:     requestID,
		ownerToken:    ownerToken,
	}}, nil
}

func (s *PostgresIdempotencyStore) Complete(
	ctx context.Context,
	reservation idempotencyReservation,
	result response,
) error {
	encoded, err := json.Marshal(result)
	if err != nil {
		return err
	}
	rows, err := sqlcgen.New(s.pool).CompleteAlexaRequestIdempotency(ctx, sqlcgen.CompleteAlexaRequestIdempotencyParams{
		ApplicationID: reservation.applicationID,
		RequestID:     reservation.requestID,
		OwnerToken:    reservation.ownerToken,
		ResponseJson:  encoded,
		ExpiresAt:     timestamptz(s.now().Add(s.resultTTL)),
	})
	if err != nil {
		return err
	}
	if rows != 1 {
		return errIdempotencyReservationLost
	}
	return nil
}

func timestamptz(value time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: value, Valid: true}
}

// memoryIdempotencyStore is deliberately test-only. Production handlers must
// receive NewPostgresIdempotencyStore from the server composition root.
type memoryIdempotencyStore struct {
	mu        sync.Mutex
	entries   map[string]*memoryIdempotencyEntry
	resultTTL time.Duration
	leaseTTL  time.Duration
	now       func() time.Time
}

type memoryIdempotencyEntry struct {
	fingerprint string
	status      string
	result      *response
	ownerToken  string
	leaseUntil  time.Time
	expiresAt   time.Time
}

func newMemoryIdempotencyStore(resultTTL, leaseTTL time.Duration) *memoryIdempotencyStore {
	return &memoryIdempotencyStore{
		entries:   make(map[string]*memoryIdempotencyEntry),
		resultTTL: resultTTL,
		leaseTTL:  leaseTTL,
		now:       time.Now,
	}
}

func (s *memoryIdempotencyStore) Acquire(
	_ context.Context,
	applicationID string,
	requestID string,
	fingerprint string,
) (idempotencyDecision, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	key := applicationID + "\x00" + requestID
	entry, ok := s.entries[key]
	if !ok {
		ownerToken := uuid.NewString()
		s.entries[key] = &memoryIdempotencyEntry{
			fingerprint: fingerprint,
			status:      "pending",
			ownerToken:  ownerToken,
			leaseUntil:  now.Add(s.leaseTTL),
		}
		return idempotencyDecision{reservation: idempotencyReservation{applicationID, requestID, ownerToken}}, nil
	}
	if entry.status == "completed" && !now.Before(entry.expiresAt) {
		ownerToken := uuid.NewString()
		entry.fingerprint = fingerprint
		entry.status = "pending"
		entry.result = nil
		entry.ownerToken = ownerToken
		entry.leaseUntil = now.Add(s.leaseTTL)
		entry.expiresAt = time.Time{}
		return idempotencyDecision{reservation: idempotencyReservation{applicationID, requestID, ownerToken}}, nil
	}
	if entry.fingerprint != fingerprint {
		return idempotencyDecision{}, errRequestIDPayloadMismatch
	}
	if entry.status == "completed" {
		result := *entry.result
		return idempotencyDecision{response: &result}, nil
	}
	if entry.leaseUntil.After(now) {
		return idempotencyDecision{pending: true}, nil
	}
	ownerToken := uuid.NewString()
	entry.ownerToken = ownerToken
	entry.leaseUntil = now.Add(s.leaseTTL)
	return idempotencyDecision{reservation: idempotencyReservation{applicationID, requestID, ownerToken}}, nil
}

func (s *memoryIdempotencyStore) Complete(_ context.Context, reservation idempotencyReservation, result response) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := reservation.applicationID + "\x00" + reservation.requestID
	entry, ok := s.entries[key]
	if !ok || entry.status != "pending" || entry.ownerToken != reservation.ownerToken {
		return errIdempotencyReservationLost
	}
	entry.status = "completed"
	entry.result = &result
	entry.expiresAt = s.now().Add(s.resultTTL)
	return nil
}
