package sync

import (
	"github.com/fmpwizard/go-quilljs-delta/delta"
)

// CloneDelta duplicates the delta struct and its underlying slices/pointers
// to prevent silent memory aliasing mutations when composing or transforming.
func CloneDelta(d *delta.Delta) *delta.Delta {
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

// SafeTransform wraps delta.Transform with deep-copy safety.
func SafeTransform(a, b *delta.Delta, priority bool) *delta.Delta {
	aCopy := CloneDelta(a)
	bCopy := CloneDelta(b)
	res := bCopy.Transform(*aCopy, priority)
	return CloneDelta(res)
}

// SafeCompose wraps delta.Compose with deep-copy safety.
func SafeCompose(a, b *delta.Delta) *delta.Delta {
	aCopy := CloneDelta(a)
	bCopy := CloneDelta(b)
	res := aCopy.Compose(*bCopy)
	return CloneDelta(res)
}
