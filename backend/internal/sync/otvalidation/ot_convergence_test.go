package otvalidation

import (
	"encoding/json"
	"math/rand"
	"testing"
	"time"

	"github.com/RigleyC/supanotes/internal/sync"
	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
)

// Invariant: Base.Compose(A).Compose(B.Transform(A, false)) == Base.Compose(B).Compose(A.Transform(B, true))
func assertConvergence(t *testing.T, base, a, b *delta.Delta) {
	aPrime := sync.SafeTransform(a, b, true)
	bPrime := sync.SafeTransform(b, a, false)

	docA := sync.SafeCompose(sync.SafeCompose(base, a), bPrime)
	docB := sync.SafeCompose(sync.SafeCompose(base, b), aPrime)

	jsonA, errA := json.Marshal(docA.Ops)
	jsonB, errB := json.Marshal(docB.Ops)

	if errA != nil || errB != nil {
		t.Fatalf("Failed to serialize ops to JSON: %v, %v", errA, errB)
	}

	assert.JSONEq(t, string(jsonA), string(jsonB), "Divergence detected!\nBase: %+v\nDelta A: %+v\nDelta B: %+v\nDelta A': %+v\nDelta B': %+v\nDoc A: %s\nDoc B: %s\n",
		base.Ops, a.Ops, b.Ops, aPrime.Ops, bPrime.Ops, string(jsonA), string(jsonB))
}

// TestOT_RegressionSliceSharing asserts that our safe compose wrapper handles
// slice aliasing and doesn't silently mutate parallel delta evaluations in memory.
func TestOT_RegressionSliceSharing(t *testing.T) {
	baseText := "O rato roeu a roupa do rei de Roma."
	baseDoc := delta.New(nil).Insert(baseText, nil)

	// Delta A and B that triggered the slice capacity append reuse bug
	a := delta.New(nil).Delete(34).Retain(1, nil)
	b := delta.New(nil).Insert("wm9", nil).Retain(1, nil).Delete(32)

	// We must evaluate them in sequence, verifying that docA is not silently mutated
	// to "wm9O" (due to B appending "O" into the shared underlying capacity array).
	assertConvergence(t, baseDoc, a, b)
}

func TestOT_ConcurrentInsertSamePosition(t *testing.T) {
	base := delta.New(nil).Insert("Hello", nil)
	a := delta.New(nil).Retain(5, nil).Insert(" World", nil)
	b := delta.New(nil).Retain(5, nil).Insert(" Guys", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_DeleteOverlappingInsert(t *testing.T) {
	base := delta.New(nil).Insert("Hello World", nil)
	a := delta.New(nil).Retain(6, nil).Delete(5)
	b := delta.New(nil).Retain(6, nil).Insert("Earth", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_InsertInsideDeleteRange(t *testing.T) {
	base := delta.New(nil).Insert("Hello World", nil)
	a := delta.New(nil).Retain(3, nil).Delete(5)
	b := delta.New(nil).Retain(5, nil).Insert("X", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_ConflictingAttributes(t *testing.T) {
	base := delta.New(nil).Insert("Hello World", nil)
	a := delta.New(nil).Retain(6, nil).Retain(5, map[string]interface{}{"bold": true})
	b := delta.New(nil).Retain(6, nil).Retain(5, map[string]interface{}{"italic": true})

	assertConvergence(t, base, a, b)
}

func randomString(n int, r *rand.Rand) string {
	var letters = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")
	s := make([]rune, n)
	for i := range s {
		s[i] = letters[r.Intn(len(letters))]
	}
	return string(s)
}

func generateRandomDelta(docLength int, r *rand.Rand) *delta.Delta {
	d := delta.New(nil)
	cursor := 0
	actionsCount := r.Intn(3) + 1

	for i := 0; i < actionsCount; i++ {
		if cursor >= docLength {
			d.Insert(randomString(r.Intn(5)+1, r), nil)
			break
		}

		actionType := r.Intn(3) // 0: Retain, 1: Insert, 2: Delete
		switch actionType {
		case 0: // Retain
			remLength := docLength - cursor
			if remLength <= 0 {
				continue
			}
			retainLen := r.Intn(remLength) + 1
			var attrs map[string]interface{}
			if r.Float32() < 0.3 {
				attrs = map[string]interface{}{"bold": true}
			}
			d.Retain(retainLen, attrs)
			cursor += retainLen
		case 1: // Insert
			d.Insert(randomString(r.Intn(5)+1, r), nil)
		case 2: // Delete
			remLength := docLength - cursor
			if remLength <= 0 {
				continue
			}
			deleteLen := r.Intn(remLength) + 1
			d.Delete(deleteLen)
			cursor += deleteLen
		}
	}
	return d
}

func TestOT_FuzzingConvergence(t *testing.T) {
	seed := time.Now().UnixNano()
	r := rand.New(rand.NewSource(seed))
	t.Logf("[OT Fuzz] Starting fuzzing with seed: %d", seed)

	iterations := 1000
	for i := 0; i < iterations; i++ {
		baseText := "O rato roeu a roupa do rei de Roma."
		baseDoc := delta.New(nil).Insert(baseText, nil)
		docLength := len(baseText)

		deltaA := generateRandomDelta(docLength, r)
		deltaB := generateRandomDelta(docLength, r)

		assertConvergence(t, baseDoc, deltaA, deltaB)
	}
}
