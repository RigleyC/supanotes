package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/reearth/ygo/crdt"
)

type Step struct {
	Client        string `json:"client"`
	Action        string `json:"action"`
	Name          string `json:"name"`
	Index         int    `json:"index"`
	Length        int    `json:"length"`
	Value         any    `json:"value"`
	Key           string `json:"key"`
	ID            string `json:"id"`
	StateVectorID string `json:"state_vector_id"`
	DiffID        string `json:"diff_id"`
	SnapshotID    string `json:"snapshot_id"`
	SourceClient  string `json:"source_client"`
}

type StepsData struct {
	Name     string `json:"name"`
	Clients  []string `json:"clients"`
	Steps    []Step   `json:"steps"`
	Expected struct {
		TextAnyOf map[string][]string `json:"text_any_of"`
	} `json:"expected"`
}

type ExpectedData struct {
	States    map[string]map[string]any `json:"states"`
	TextAnyOf map[string][]string       `json:"text_any_of"`
}

func main() {
	mode := flag.String("mode", "verify", "Execution mode: generate or verify")
	targetCase := flag.String("case", "", "Target single case to run")
	flag.Parse()

	casesDir := "../cases"
	entries, err := os.ReadDir(casesDir)
	if err != nil {
		fmt.Printf("Error reading cases directory: %v\n", err)
		os.Exit(1)
	}

	var cases []string
	for _, entry := range entries {
		if entry.IsDir() {
			cases = append(cases, entry.Name())
		}
	}
	sort.Strings(cases)

	failed := false
	for _, caseName := range cases {
		if *targetCase != "" && caseName != *targetCase {
			continue
		}
		fmt.Printf("Running case: %s in %s mode...\n", caseName, *mode)
		err := runCase(caseName, *mode)
		if err != nil {
			fmt.Printf("❌ Case %s FAILED: %v\n", caseName, err)
			failed = true
		} else {
			fmt.Printf("✅ Case %s passed\n", caseName)
		}
	}

	if failed {
		os.Exit(1)
	}
}

func runCase(caseName, mode string) error {
	stepsPath := filepath.Join("../cases", caseName, "steps.json")
	stepsBytes, err := os.ReadFile(stepsPath)
	if err != nil {
		return fmt.Errorf("failed to read steps.json: %w", err)
	}

	var data StepsData
	if err := json.Unmarshal(stepsBytes, &data); err != nil {
		return fmt.Errorf("failed to parse steps.json: %w", err)
	}

	// Scan steps to determine type schemas
	typeSchemas := make(map[string]string)
	for _, step := range data.Steps {
		if step.Name == "" {
			continue
		}
		if strings.HasPrefix(step.Action, "text_") {
			typeSchemas[step.Name] = "text"
		} else if strings.HasPrefix(step.Action, "map_") {
			typeSchemas[step.Name] = "map"
		} else if strings.HasPrefix(step.Action, "array_") {
			typeSchemas[step.Name] = "array"
		}
	}

	// Initialize documents with gc: false and deterministic client IDs
	docs := make(map[string]*crdt.Doc)
	for _, clientName := range data.Clients {
		if len(clientName) == 0 {
			continue
		}
		clientID := uint32(clientName[0])
		doc := crdt.New(crdt.WithGC(false), crdt.WithClientID(crdt.ClientID(clientID)))
		docs[clientName] = doc

		// Pre-initialize types
		for typeName, typeKind := range typeSchemas {
			switch typeKind {
			case "text":
				doc.GetText(typeName)
			case "map":
				doc.GetMap(typeName)
			case "array":
				doc.GetArray(typeName)
			}
		}
	}

	updates := make(map[string][]byte)
	stateVectors := make(map[string][]byte)
	snapshots := make(map[string]*crdt.Snapshot)

	ensureFixturesDir := func() {
		os.MkdirAll(filepath.Join("../cases", caseName, "fixtures"), 0755)
	}

	for i, step := range data.Steps {
		switch step.Action {
		case "text_insert":
			doc := docs[step.Client]
			txt := doc.GetText(step.Name)
			valStr, ok := step.Value.(string)
			if !ok {
				return fmt.Errorf("step %d: text_insert value is not string", i)
			}
			doc.Transact(func(txn *crdt.Transaction) {
				txt.Insert(txn, step.Index, valStr, nil)
			})

		case "text_delete":
			doc := docs[step.Client]
			txt := doc.GetText(step.Name)
			doc.Transact(func(txn *crdt.Transaction) {
				txt.Delete(txn, step.Index, step.Length)
			})

		case "map_set":
			doc := docs[step.Client]
			m := doc.GetMap(step.Name)
			doc.Transact(func(txn *crdt.Transaction) {
				m.Set(txn, step.Key, step.Value)
			})

		case "array_insert":
			doc := docs[step.Client]
			arr := doc.GetArray(step.Name)
			doc.Transact(func(txn *crdt.Transaction) {
				arr.Insert(txn, step.Index, []any{step.Value})
			})

		case "export_update":
			doc := docs[step.Client]
			upd := crdt.EncodeStateAsUpdateV1(doc, nil)
			updates[step.ID] = upd
			if mode == "generate" {
				ensureFixturesDir()
				path := filepath.Join("../cases", caseName, "fixtures", step.ID+".bin")
				if err := os.WriteFile(path, upd, 0644); err != nil {
					return fmt.Errorf("failed to write fixture %s: %w", step.ID, err)
				}
			}

		case "import_update":
			doc := docs[step.Client]
			var updBytes []byte
			if mode == "verify" {
				path := filepath.Join("../cases", caseName, "fixtures", step.ID+".bin")
				var err error
				updBytes, err = os.ReadFile(path)
				if err != nil {
					return fmt.Errorf("failed to read fixture %s: %w", step.ID, err)
				}
			} else {
				updBytes = updates[step.ID]
			}
			if err := crdt.ApplyUpdateV1(doc, updBytes, nil); err != nil {
				return fmt.Errorf("step %d: failed to apply update: %w", i, err)
			}

		case "export_state_vector":
			doc := docs[step.Client]
			sv := crdt.EncodeStateVectorV1(doc)
			stateVectors[step.ID] = sv

		case "import_state_vector_and_export_diff":
			doc := docs[step.Client]
			svBytes := stateVectors[step.StateVectorID]
			sv, err := crdt.DecodeStateVectorV1(svBytes)
			if err != nil {
				return fmt.Errorf("step %d: failed to decode state vector: %w", i, err)
			}
			diff := crdt.EncodeStateAsUpdateV1(doc, sv)
			updates[step.DiffID] = diff
			if mode == "generate" {
				ensureFixturesDir()
				path := filepath.Join("../cases", caseName, "fixtures", step.DiffID+".bin")
				if err := os.WriteFile(path, diff, 0644); err != nil {
					return fmt.Errorf("failed to write diff fixture %s: %w", step.DiffID, err)
				}
			}

		case "take_snapshot":
			doc := docs[step.Client]
			snap := crdt.CaptureSnapshot(doc)
			snapshots[step.ID] = snap
			if mode == "generate" {
				ensureFixturesDir()
				bytes := crdt.EncodeSnapshot(snap)
				path := filepath.Join("../cases", caseName, "fixtures", step.ID+".snap")
				if err := os.WriteFile(path, bytes, 0644); err != nil {
					return fmt.Errorf("failed to write snapshot fixture %s: %w", step.ID, err)
				}
			}

		case "restore_snapshot":
			sourceDoc := docs[step.SourceClient]
			var snap *crdt.Snapshot
			if mode == "verify" {
				path := filepath.Join("../cases", caseName, "fixtures", step.SnapshotID+".snap")
				bytes, err := os.ReadFile(path)
				if err != nil {
					return fmt.Errorf("failed to read snapshot fixture %s: %w", step.SnapshotID, err)
				}
				snap, err = crdt.DecodeSnapshot(bytes)
				if err != nil {
					return fmt.Errorf("failed to decode snapshot: %w", err)
				}
			} else {
				snap = snapshots[step.SnapshotID]
			}
			restoredDoc, err := crdt.CreateDocFromSnapshot(sourceDoc, snap)
			if err != nil {
				return fmt.Errorf("step %d: failed to create doc from snapshot: %w", i, err)
			}
			docs[step.Client] = restoredDoc

		default:
			return fmt.Errorf("step %d: unknown action %q", i, step.Action)
		}
	}

	// Gather final states
	finalStates := make(map[string]map[string]any)
	for clientName, doc := range docs {
		state := make(map[string]any)

		textState := make(map[string]string)
		mapState := make(map[string]any)
		arrayState := make(map[string]any)

		for typeName, typeKind := range typeSchemas {
			switch typeKind {
			case "text":
				textState[typeName] = doc.GetText(typeName).ToString()
			case "map":
				var mapVal map[string]any
				jsonBytes, err := doc.GetMap(typeName).ToJSON()
				if err == nil {
					json.Unmarshal(jsonBytes, &mapVal)
				}
				if mapVal != nil {
					mapState[typeName] = mapVal
				}
			case "array":
				var arrVal []any
				jsonBytes, err := doc.GetArray(typeName).ToJSON()
				if err == nil {
					json.Unmarshal(jsonBytes, &arrVal)
				}
				if arrVal != nil {
					arrayState[typeName] = arrVal
				}
			}
		}

		if len(textState) > 0 {
			state["text"] = textState
		}
		if len(mapState) > 0 {
			state["map"] = mapState
		}
		if len(arrayState) > 0 {
			state["array"] = arrayState
		}

		finalStates[clientName] = state
	}

	expectedPath := filepath.Join("../cases", caseName, "expected.json")
	if mode == "generate" {
		// Output expected.json
		outputData := ExpectedData{
			States: finalStates,
		}
		if data.Expected.TextAnyOf != nil {
			outputData.TextAnyOf = data.Expected.TextAnyOf
		}
		outBytes, err := json.MarshalIndent(outputData, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal expected data: %w", err)
		}
		if err := os.WriteFile(expectedPath, outBytes, 0644); err != nil {
			return fmt.Errorf("failed to write expected.json: %w", err)
		}
	} else {
		// Verify document states match expected.json
		expectedBytes, err := os.ReadFile(expectedPath)
		if err != nil {
			return fmt.Errorf("failed to read expected.json: %w", err)
		}
		var expectedData ExpectedData
		if err := json.Unmarshal(expectedBytes, &expectedData); err != nil {
			return fmt.Errorf("failed to parse expected.json: %w", err)
		}

		for clientName, expectedState := range expectedData.States {
			actualState := finalStates[clientName]

			// Check text
			if expectedText, ok := expectedState["text"].(map[string]any); ok {
				actualText, _ := actualState["text"].(map[string]string)
				for key, val := range expectedText {
					expectedVal, _ := val.(string)
					actualVal := actualText[key]
					if expectedVal != actualVal {
						return fmt.Errorf("client %s text field %s mismatch: expected %q, got %q", clientName, key, expectedVal, actualVal)
					}
				}
			}

			// Check map
			if expectedMap, ok := expectedState["map"].(map[string]any); ok {
				actualMap, _ := actualState["map"].(map[string]any)
				if !reflect.DeepEqual(expectedMap, actualMap) {
					return fmt.Errorf("client %s map mismatch: expected %v, got %v", clientName, expectedMap, actualMap)
				}
			}

			// Check array
			if expectedArray, ok := expectedState["array"].(map[string]any); ok {
				actualArray, _ := actualState["array"].(map[string]any)
				if !reflect.DeepEqual(expectedArray, actualArray) {
					return fmt.Errorf("client %s array mismatch: expected %v, got %v", clientName, expectedArray, actualArray)
				}
			}

			// Check any_of patterns (like anti-interleaving)
			if expectedData.TextAnyOf != nil {
				actualText, _ := actualState["text"].(map[string]string)
				for key, options := range expectedData.TextAnyOf {
					actualVal := actualText[key]
					found := false
					for _, opt := range options {
						if opt == actualVal {
							found = true
							break
						}
					}
					if !found {
						return fmt.Errorf("client %s text field %s is %q, expected one of %v", clientName, key, actualVal, options)
					}
				}
			}
		}
	}

	return nil
}

func hashString(s string) string {
	h := sha256.New()
	io.WriteString(h, s)
	return fmt.Sprintf("%x", h.Sum(nil))
}

func byteSliceEqual(a, b []byte) bool {
	return bytes.Equal(a, b)
}
