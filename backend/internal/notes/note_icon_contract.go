package notes

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

// Covers the longest current Unicode emoji sequences, including ZWJ and skin
// tone modifiers, while keeping arbitrary payloads out of note metadata.
const maxNoteIconBytes = 64

// NoteIconUpdate is the three-state patch for note_icon.
//
// The fields are private so callers cannot create an invalid combination such
// as a value with Set=false. Use the constructors in this file to construct
// one of the valid states.
type NoteIconUpdate struct {
	kind  noteIconUpdateKind
	value []byte
}

type noteIconUpdateKind uint8

const (
	noteIconOmitted noteIconUpdateKind = iota
	noteIconCleared
	noteIconSet
)

type noteIconPayload struct {
	Kind     string          `json:"kind"`
	Value    string          `json:"value"`
	ColorKey json.RawMessage `json:"color_key"`
}

func omitNoteIcon() NoteIconUpdate {
	return NoteIconUpdate{kind: noteIconOmitted}
}

func clearNoteIcon() NoteIconUpdate {
	return NoteIconUpdate{kind: noteIconCleared}
}

func valueNoteIcon(raw []byte) NoteIconUpdate {
	return NoteIconUpdate{
		kind:  noteIconSet,
		value: append([]byte(nil), raw...),
	}
}

func (u NoteIconUpdate) IsSet() bool {
	return u.kind != noteIconOmitted
}

func (u NoteIconUpdate) JSON() []byte {
	return append([]byte(nil), u.value...)
}

// This is the server-side security allowlist for the same wire identifiers
// exposed by the Flutter catalog. Presentation details stay on the client.
var catalogIconIDs = map[string]struct{}{
	"wallet": {}, "arrow_down": {}, "star": {}, "lock": {},
	"home": {}, "calendar": {}, "basket": {}, "travel": {},
	"book": {}, "bookmark": {}, "code": {}, "braces": {},
	"building": {}, "sparkles": {}, "camera": {}, "car": {},
	"cart": {}, "warning": {}, "chart": {}, "chat": {},
	"cloud": {}, "settings": {}, "crown": {}, "monitor": {},
	"money": {}, "globe": {}, "eye": {}, "fire": {},
	"flag": {}, "game": {},
}

var catalogColorKeys = map[string]struct{}{
	"red": {}, "orange": {}, "yellow": {}, "green": {},
	"teal": {}, "blue": {}, "indigo": {}, "purple": {},
	"pink": {}, "brown": {}, "gray": {}, "black": {},
}

// parseNoteIconPayload separates an omitted field from an explicit null and
// validates the object before it crosses into the service and database layers.
func parseNoteIconPayload(raw []byte) (NoteIconUpdate, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 {
		return omitNoteIcon(), nil
	}
	if bytes.Equal(trimmed, []byte("null")) {
		return clearNoteIcon(), nil
	}

	var decoded noteIconPayload
	if err := json.Unmarshal(trimmed, &decoded); err != nil {
		return NoteIconUpdate{}, errors.New("invalid note icon")
	}
	if err := validateNoteIcon(decoded); err != nil {
		return NoteIconUpdate{}, err
	}
	return valueNoteIcon(trimmed), nil
}

func validateNoteIcon(icon noteIconPayload) error {
	if icon.Kind == "" {
		return fmt.Errorf("note icon kind is required")
	}
	if strings.TrimSpace(icon.Value) == "" {
		return fmt.Errorf("note icon value is required")
	}
	switch icon.Kind {
	case "emoji":
		if len(icon.ColorKey) > 0 {
			return fmt.Errorf("emoji cannot have a color")
		}
		if !utf8.ValidString(icon.Value) || !containsEmojiCodePoint(icon.Value) || len(icon.Value) > maxNoteIconBytes {
			return fmt.Errorf("invalid emoji value")
		}
	case "catalog":
		if _, ok := catalogIconIDs[icon.Value]; !ok {
			return fmt.Errorf("unknown catalog icon")
		}
		color, ok := noteIconColorKey(icon.ColorKey)
		if !ok {
			return fmt.Errorf("catalog icon color is required")
		}
		if _, ok := catalogColorKeys[color]; !ok {
			return fmt.Errorf("unknown catalog icon color")
		}
	default:
		return fmt.Errorf("unknown note icon kind")
	}
	return nil
}

func containsEmojiCodePoint(value string) bool {
	for _, runeValue := range value {
		if (runeValue >= 0x1F000 && runeValue <= 0x1FAFF) ||
			(runeValue >= 0x2300 && runeValue <= 0x23FF) ||
			(runeValue >= 0x2600 && runeValue <= 0x27BF) ||
			(runeValue >= 0x2B00 && runeValue <= 0x2BFF) {
			return true
		}
	}
	return false
}

func noteIconColorKey(raw json.RawMessage) (string, bool) {
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return "", false
	}
	var color string
	if err := json.Unmarshal(raw, &color); err != nil || color == "" {
		return "", false
	}
	return color, true
}
