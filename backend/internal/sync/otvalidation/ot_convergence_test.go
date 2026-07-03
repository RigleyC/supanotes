package otvalidation

import (
	"encoding/json"
	"math/rand"
	"testing"
	"time"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
)

func deepCopyDelta(d *delta.Delta) *delta.Delta {
	if d == nil {
		return nil
	}
	ops := make([]delta.Op, len(d.Ops))
	for i, op := range d.Ops {
		ops[i] = op
		if op.Insert != nil {
			ops[i].Insert = append([]rune(nil), op.Insert...)
		}
		if op.Retain != nil {
			val := *op.Retain
			ops[i].Retain = &val
		}
		if op.Delete != nil {
			val := *op.Delete
			ops[i].Delete = &val
		}
		if op.Attributes != nil {
			attrs := make(map[string]interface{})
			for k, v := range op.Attributes {
				attrs[k] = v
			}
			ops[i].Attributes = attrs
		}
	}
	return delta.New(ops)
}

// Invariant: Base.Compose(A).Compose(B.Transform(A, false)) == Base.Compose(B).Compose(A.Transform(B, true))
func assertConvergence(t *testing.T, base, a, b *delta.Delta) {
	// Deep copy inputs to prevent slice sharing side-effects
	aCopy := deepCopyDelta(a)
	bCopy := deepCopyDelta(b)
	baseCopy1 := deepCopyDelta(base)
	baseCopy2 := deepCopyDelta(base)

	aPrime := bCopy.Transform(*aCopy, true)
	bPrime := aCopy.Transform(*bCopy, false)

	// Clone primes since they might contain slice references from transforms
	aPrimeCopy := deepCopyDelta(aPrime)
	bPrimeCopy := deepCopyDelta(bPrime)

	docA := baseCopy1.Compose(*aCopy).Compose(*bPrimeCopy)
	docB := baseCopy2.Compose(*bCopy).Compose(*aPrimeCopy)

	jsonA, errA := json.Marshal(docA.Ops)
	jsonB, errB := json.Marshal(docB.Ops)

	if errA != nil || errB != nil {
		t.Fatalf("Failed to serialize ops to JSON: %v, %v", errA, errB)
	}

	assert.JSONEq(t, string(jsonA), string(jsonB), "Divergence detected!\nBase: %+v\nDelta A: %+v\nDelta B: %+v\nDelta A': %+v\nDelta B': %+v\nDoc A: %s\nDoc B: %s\n",
		base.Ops, a.Ops, b.Ops, aPrime.Ops, bPrime.Ops, string(jsonA), string(jsonB))
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
