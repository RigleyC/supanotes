package sync

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeQueryRow struct {
	scanErr error
	machine string
}

func (f fakeQueryRow) Scan(dest ...any) error {
	if f.scanErr != nil {
		return f.scanErr
	}
	if s, ok := dest[0].(*string); ok {
		*s = f.machine
	}
	return nil
}

type fakePoolForLease struct {
	rows map[string]fakeQueryRow
}

func (f *fakePoolForLease) QueryRow(_ context.Context, _ string, args ...any) fakeQueryRow {
	if len(args) >= 2 {
		noteID, _ := args[0].(string)
		machineID, _ := args[1].(string)
		if machineID == "machine-err" {
			return fakeQueryRow{scanErr: errors.New("conn closed")}
		}
		if row, ok := f.rows[noteID]; ok && row.machine != machineID {
			return fakeQueryRow{scanErr: pgx.ErrNoRows}
		}
		return fakeQueryRow{machine: machineID}
	}
	return fakeQueryRow{scanErr: errors.New("unexpected args")}
}

type unitLeaseManager struct {
	pool *fakePoolForLease
}

func (m *unitLeaseManager) AcquireLease(ctx context.Context, noteID, machineID string) (string, bool, error) {
	row := m.pool.QueryRow(ctx, "", noteID, machineID)
	var winner string
	err := row.Scan(&winner)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", false, nil
		}
		return "", false, err
	}
	return winner, winner == machineID, nil
}

func TestUnitLeaseAcquire_FirstAcquireWins(t *testing.T) {
	mgr := &unitLeaseManager{pool: &fakePoolForLease{rows: map[string]fakeQueryRow{}}}
	winner, ok, err := mgr.AcquireLease(context.Background(), "note-1", "machine-a")
	require.NoError(t, err)
	assert.True(t, ok)
	assert.Equal(t, "machine-a", winner)
}

func TestUnitLeaseAcquire_SecondAcquirerLoses(t *testing.T) {
	mgr := &unitLeaseManager{pool: &fakePoolForLease{rows: map[string]fakeQueryRow{
		"note-1": {machine: "machine-a"},
	}}}
	winner, ok, err := mgr.AcquireLease(context.Background(), "note-1", "machine-b")
	require.NoError(t, err)
	assert.False(t, ok)
	assert.Equal(t, "", winner)
}

func TestUnitLeaseAcquire_DBErrorPropagates(t *testing.T) {
	mgr := &unitLeaseManager{pool: &fakePoolForLease{rows: map[string]fakeQueryRow{}}}
	_, _, err := mgr.AcquireLease(context.Background(), "note-1", "machine-err")
	require.Error(t, err)
}
