package utils

import (
	"sort"
	"testing"
)

func TestGenerateKeyBetween(t *testing.T) {
	t.Run("between two strings", func(t *testing.T) {
		a := GenerateKeyBetween("a0", "a2")
		if a <= "a0" || a >= "a2" {
			t.Errorf("expected key between a0 and a2, got %s", a)
		}
	})

	t.Run("at the beginning", func(t *testing.T) {
		a := GenerateKeyBetween("", "a0")
		if a == "" || a >= "a0" {
			t.Errorf("expected key before a0, got %s", a)
		}
	})

	t.Run("at the end", func(t *testing.T) {
		a := GenerateKeyBetween("a0", "")
		if a <= "a0" {
			t.Errorf("expected key after a0, got %s", a)
		}
	})

	t.Run("both empty", func(t *testing.T) {
		a := GenerateKeyBetween("", "")
		if a == "" {
			t.Errorf("expected non-empty key, got empty")
		}
	})

	t.Run("multiple calls produce ordered keys", func(t *testing.T) {
		var keys []string
		pos := ""
		for range 10 {
			key := GenerateKeyBetween(pos, "")
			if key <= pos {
				t.Fatalf("expected key > %s, got %s", pos, key)
			}
			pos = key
			keys = append(keys, key)
		}
		if !sort.StringsAreSorted(keys) {
			t.Errorf("expected sorted keys, got %v", keys)
		}
	})

	t.Run("inserting between existing keys", func(t *testing.T) {
		keys := []string{GenerateKeyBetween("", "")}
		for range 5 {
			keys = append(keys, GenerateKeyBetween(keys[len(keys)-1], ""))
		}
		for i := 0; i < len(keys)-1; i++ {
			mid := GenerateKeyBetween(keys[i], keys[i+1])
			if mid <= keys[i] || mid >= keys[i+1] {
				t.Errorf("expected key between %s and %s, got %s at index %d", keys[i], keys[i+1], mid, i)
			}
		}
	})
}
