package noteoperations

import (
	"bytes"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/fmpwizard/go-quilljs-delta/delta"
)

func compareUUID(a, b pgtype.UUID) int {
	if !a.Valid || !b.Valid {
		return 0
	}
	return bytes.Compare(a.Bytes[:], b.Bytes[:])
}

// serverHasPriority returns true when the server's operation (serverActorID, serverOpID)
// should take priority over the client's operation (clientActorID, clientOpID).
// Lower (actorId, operationId) tuple wins.
func serverHasPriority(serverActorID, clientActorID, serverOpID, clientOpID pgtype.UUID) bool {
	cmp := compareUUID(serverActorID, clientActorID)
	if cmp != 0 {
		return cmp < 0
	}
	return compareUUID(serverOpID, clientOpID) < 0
}



func concurrentDeltasForBlock(
	operations []Operation,
	blockID string,
) ([]delta.Op, error) {
	var allOps []delta.Op
	for _, op := range operations {
		if op.Kind != string(KindTextDelta) {
			continue
		}
		if op.BlockID.Valid && op.BlockID.String == blockID {
			d, err := parseDeltaFromPayload(op.Payload)
			if err != nil {
				return nil, fmt.Errorf("unmarshal concurrent ops: %w", err)
			}
			allOps = append(allOps, d.Ops...)
		}
	}
	return allOps, nil
}
