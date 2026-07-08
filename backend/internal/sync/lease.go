package sync

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type LeaseManager interface {
	AcquireLease(ctx context.Context, noteID string, machineID string) (bool, error)
	RenewLease(ctx context.Context, noteID string, machineID string) error
	ReleaseLease(ctx context.Context, noteID string, machineID string) error
	GetLeaseMachine(ctx context.Context, noteID string) (string, error)
}

type leaseManager struct {
	pool *pgxpool.Pool
}

func NewLeaseManager(pool *pgxpool.Pool) LeaseManager {
	return &leaseManager{pool: pool}
}

const leaseDuration = 60 * time.Second

func (m *leaseManager) AcquireLease(ctx context.Context, noteID string, machineID string) (bool, error) {
	query := `
		INSERT INTO note_ws_leases (note_id, machine_id, expires_at)
		VALUES ($1, $2, NOW() + $3::interval)
		ON CONFLICT (note_id) DO UPDATE
		SET machine_id = EXCLUDED.machine_id, expires_at = NOW() + $3::interval
		WHERE note_ws_leases.expires_at < NOW() OR note_ws_leases.machine_id = EXCLUDED.machine_id
		RETURNING true;
	`
	interval := leaseDuration.String()
	var acquired bool
	err := m.pool.QueryRow(ctx, query, noteID, machineID, interval).Scan(&acquired)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return acquired, nil
}

func (m *leaseManager) RenewLease(ctx context.Context, noteID string, machineID string) error {
	query := `
		UPDATE note_ws_leases
		SET expires_at = NOW() + $3::interval
		WHERE note_id = $1 AND machine_id = $2
	`
	interval := leaseDuration.String()
	_, err := m.pool.Exec(ctx, query, noteID, machineID, interval)
	return err
}

func (m *leaseManager) ReleaseLease(ctx context.Context, noteID string, machineID string) error {
	query := `
		DELETE FROM note_ws_leases
		WHERE note_id = $1 AND machine_id = $2
	`
	_, err := m.pool.Exec(ctx, query, noteID, machineID)
	return err
}

func (m *leaseManager) GetLeaseMachine(ctx context.Context, noteID string) (string, error) {
	query := `
		SELECT machine_id FROM note_ws_leases
		WHERE note_id = $1 AND expires_at > NOW()
	`
	var machineID string
	err := m.pool.QueryRow(ctx, query, noteID).Scan(&machineID)
	return machineID, err
}
