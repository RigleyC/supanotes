package ot

import (
	"encoding/json"

	thirdparty "github.com/fmpwizard/go-quilljs-delta/delta"
)

// Delta is a concurrency-safe, immutable wrapper around the third-party Delta library.
type Delta struct {
	inner *thirdparty.Delta
}

func deepCopyDelta(d *thirdparty.Delta) *thirdparty.Delta {
	if d == nil {
		return nil
	}
	ops := make([]thirdparty.Op, len(d.Ops))
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
	return thirdparty.New(ops)
}

// New returns a new safe Delta instance.
func New(ops []thirdparty.Op) Delta {
	d := thirdparty.New(ops)
	return Delta{inner: deepCopyDelta(d)}
}

// IsNil returns true if the Delta has not been initialized.
func (d Delta) IsNil() bool {
	return d.inner == nil
}

// Ops returns a copy of the underlying operations slice.
func (d Delta) Ops() []thirdparty.Op {
	if d.inner == nil {
		return nil
	}
	// Return a copy to prevent external mutation of the inner slice
	copied := deepCopyDelta(d.inner)
	return copied.Ops
}

// Insert inserts text at the end of the Delta, returning a new immutable Delta.
func (d Delta) Insert(text string, attrs map[string]interface{}) Delta {
	copied := deepCopyDelta(d.inner)
	copied.Insert(text, attrs)
	return Delta{inner: copied}
}

// Delete deletes n characters at the end of the Delta, returning a new immutable Delta.
func (d Delta) Delete(n int) Delta {
	copied := deepCopyDelta(d.inner)
	copied.Delete(n)
	return Delta{inner: copied}
}

// Retain retains n characters, returning a new immutable Delta.
func (d Delta) Retain(n int, attrs map[string]interface{}) Delta {
	copied := deepCopyDelta(d.inner)
	copied.Retain(n, attrs)
	return Delta{inner: copied}
}

// Compose returns a new Delta representing the sequential application of this Delta followed by other.
func (d Delta) Compose(other Delta) Delta {
	res := d.inner.Compose(*other.inner)
	return Delta{inner: deepCopyDelta(res)}
}

// Transform transforms other against this Delta, returning a new transformed Delta.
func (d Delta) Transform(other Delta, priority bool) Delta {
	res := d.inner.Transform(*other.inner, priority)
	return Delta{inner: deepCopyDelta(res)}
}

// MarshalJSON implements the json.Marshaler interface to serialize directly into a Quill-compatible operations array.
func (d Delta) MarshalJSON() ([]byte, error) {
	if d.inner == nil {
		return json.Marshal([]interface{}{})
	}
	return json.Marshal(d.inner.Ops)
}

// UnmarshalJSON implements the json.Unmarshaler interface to deserialize from a Quill-compatible operations array.
func (d *Delta) UnmarshalJSON(data []byte) error {
	var ops []thirdparty.Op
	if err := json.Unmarshal(data, &ops); err != nil {
		return err
	}
	d.inner = deepCopyDelta(thirdparty.New(ops))
	return nil
}
