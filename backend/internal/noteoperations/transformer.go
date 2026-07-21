package noteoperations

import (
	"fmt"

	"github.com/fmpwizard/go-quilljs-delta/delta"
)

func TransformDeltas(clientDelta, serverDelta []delta.Op) ([]delta.Op, error) {
	client := delta.New(clientDelta)
	server := delta.New(serverDelta)

	result := server.Transform(*client, true)
	return result.Ops, nil
}

func ComposeDeltas(base, change []delta.Op) ([]delta.Op, error) {
	baseDelta := delta.New(base)
	changeDelta := delta.New(change)

	result := baseDelta.Compose(*changeDelta)
	return result.Ops, nil
}

func InvertDelta(deltaOps, baseOps []delta.Op) ([]delta.Op, error) {
	d := delta.New(deltaOps)
	base := delta.New(baseOps)

	result := d.Invert(base)
	return result.Ops, nil
}

func TransformClientDeltasAgainstConcurrent(
	clientOps []delta.Op,
	concurrentOps []delta.Op,
) ([]delta.Op, error) {
	client := delta.New(clientOps)
	concurrent := delta.New(concurrentOps)

	result := concurrent.Transform(*client, true)
	return result.Ops, nil
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
