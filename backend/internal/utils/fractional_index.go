package utils

import (
	"roci.dev/fracdex"
)

// GenerateKeyBetween calculates a key lexicographically between a and b.
// It matches standard Figma-style fractional indexing.
func GenerateKeyBetween(a, b string) (string, error) {
	return fracdex.KeyBetween(a, b)
}
