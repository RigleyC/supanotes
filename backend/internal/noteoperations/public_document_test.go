package noteoperations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

type canonicalCorpusCase struct {
	Name     string          `json:"name"`
	Valid    bool            `json:"valid"`
	Document json.RawMessage `json:"document"`
}

func TestDecodeCanonicalDocumentMatchesSharedCorpus(t *testing.T) {
	_, sourceFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	corpusPath := filepath.Join(filepath.Dir(sourceFile), "..", "..", "..", "contracts", "note_document", "corpus.json")
	data, err := os.ReadFile(corpusPath)
	if err != nil {
		t.Fatalf("read canonical corpus: %v", err)
	}
	var cases []canonicalCorpusCase
	if err := json.Unmarshal(data, &cases); err != nil {
		t.Fatalf("decode canonical corpus: %v", err)
	}

	for _, testCase := range cases {
		t.Run(testCase.Name, func(t *testing.T) {
			_, err := DecodeCanonicalDocument(testCase.Document)
			if testCase.Valid && err != nil {
				t.Fatalf("valid fixture rejected: %v", err)
			}
			if !testCase.Valid && err == nil {
				t.Fatal("invalid fixture was accepted")
			}
		})
	}
}
