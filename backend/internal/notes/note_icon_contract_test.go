package notes

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseNoteIconPayloadDistinguishesOmittedAndClear(t *testing.T) {
	cases := []struct {
		name      string
		raw       string
		set       bool
		wantValue string
	}{
		{name: "omitted", raw: "", set: false},
		{name: "clear", raw: " null ", set: true},
		{
			name:      "value",
			raw:       `{"kind":"emoji","value":"🙂"}`,
			set:       true,
			wantValue: `{"kind":"emoji","value":"🙂"}`,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			value, err := parseNoteIconPayload([]byte(tc.raw))
			if err != nil {
				t.Fatalf("parseNoteIconPayload() error = %v", err)
			}
			if value.IsSet() != tc.set {
				t.Fatalf("set = %t, want %t", value.IsSet(), tc.set)
			}
			if string(value.JSON()) != tc.wantValue {
				t.Fatalf("value = %q, want %q", value.JSON(), tc.wantValue)
			}
		})
	}
}

func TestNoteIconUpdateConstructorsExposeOnlyTheirState(t *testing.T) {
	value := []byte(`{"kind":"emoji","value":"🙂"}`)
	update := valueNoteIcon(value)
	value[0] = 'X'

	if !update.IsSet() {
		t.Fatal("value update should be set")
	}
	if string(update.JSON()) != `{"kind":"emoji","value":"🙂"}` {
		t.Fatalf("value update was mutated through constructor input: %s", update.JSON())
	}
	if omitNoteIcon().JSON() != nil {
		t.Fatal("omitted update should have no JSON payload")
	}
	if !clearNoteIcon().IsSet() {
		t.Fatal("clear update should be set")
	}
}

func TestValidateNoteIcon(t *testing.T) {
	tests := []struct {
		name    string
		icon    noteIconPayload
		wantErr bool
	}{
		{
			name: "emoji",
			icon: noteIconPayload{Kind: "emoji", Value: "🙂"},
		},
		{
			name: "long ZWJ emoji",
			icon: noteIconPayload{Kind: "emoji", Value: "👨🏼‍❤️‍💋‍👨🏽"},
		},
		{
			name: "catalog",
			icon: noteIconPayload{
				Kind:     "catalog",
				Value:    "star",
				ColorKey: json.RawMessage(`"blue"`),
			},
		},
		{
			name: "unknown catalog id",
			icon: noteIconPayload{
				Kind:     "catalog",
				Value:    "unknown",
				ColorKey: json.RawMessage(`"blue"`),
			},
			wantErr: true,
		},
		{
			name: "emoji color",
			icon: noteIconPayload{
				Kind:     "emoji",
				Value:    "🙂",
				ColorKey: json.RawMessage(`"red"`),
			},
			wantErr: true,
		},
		{
			name:    "blank emoji",
			icon:    noteIconPayload{Kind: "emoji", Value: "   "},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := validateNoteIcon(tt.icon); (err != nil) != tt.wantErr {
				t.Fatalf("validateNoteIcon() error = %v, wantErr %t", err, tt.wantErr)
			}
		})
	}
}

func TestCatalogAllowlistMatchesWireContractFixture(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "..", "test", "fixtures", "note_icon_contract.json")
	raw, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatalf("read contract fixture: %v", err)
	}

	var fixture struct {
		MaxEmojiBytes int      `json:"max_emoji_bytes"`
		CatalogIcons  []string `json:"catalog_icons"`
		ColorKeys     []string `json:"color_keys"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatalf("decode contract fixture: %v", err)
	}
	if fixture.MaxEmojiBytes != maxNoteIconBytes {
		t.Fatalf("max emoji bytes = %d, want %d", fixture.MaxEmojiBytes, maxNoteIconBytes)
	}

	actualIcons := make([]string, 0, len(catalogIconIDs))
	for iconID := range catalogIconIDs {
		actualIcons = append(actualIcons, iconID)
	}
	actualColors := make([]string, 0, len(catalogColorKeys))
	for colorKey := range catalogColorKeys {
		actualColors = append(actualColors, colorKey)
	}

	if !sameStringSet(actualIcons, fixture.CatalogIcons) {
		t.Fatalf("catalog icon allowlist differs from fixture")
	}
	if !sameStringSet(actualColors, fixture.ColorKeys) {
		t.Fatalf("catalog color allowlist differs from fixture")
	}
}

func sameStringSet(left, right []string) bool {
	leftSet := make(map[string]struct{}, len(left))
	for _, value := range left {
		leftSet[value] = struct{}{}
	}
	rightSet := make(map[string]struct{}, len(right))
	for _, value := range right {
		rightSet[value] = struct{}{}
	}
	return reflect.DeepEqual(leftSet, rightSet)
}
