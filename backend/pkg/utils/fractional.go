package utils

import "roci.dev/fracdex"

// GenerateKeyBetween returns a key that sorts lexicographically between a and b.
// Empty a → smallest key, empty b → largest key. Matches FractionalIndex.between in Dart
// (fractional_indexing_dart and roci.dev/fracdex implement the same Greenspan algorithm).
func GenerateKeyBetween(a, b string) string {
	key, err := fracdex.KeyBetween(a, b)
	if err != nil {
		return "a0"
	}
	return key
}
