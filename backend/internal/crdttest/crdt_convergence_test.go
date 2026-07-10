package crdttest

import (
	"fmt"
	"math/rand/v2"
	"os"
	"testing"

	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMPORTANT: ygo requires GetText/GetMap to be called OUTSIDE Transact.
// Calling doc.GetText() inside a Transact closure causes a deadlock because
// GetText acquires a read lock that Transact already holds as a write lock.

// =============================================================================
// Teste 1 — Go sozinho, sem rede
// =============================================================================

func TestCRDT1_GoConvergence(t *testing.T) {
	t.Run("fixed_concurrent_inserts", func(t *testing.T) {
		docA := crdt.New(crdt.WithGC(false))
		docB := crdt.New(crdt.WithGC(false))

		// Pre-register YText outside of Transact
		textA := docA.GetText("content")
		textB := docB.GetText("content")

		const initial = "hello world"
		docA.Transact(func(txn *crdt.Transaction) {
			textA.Insert(txn, 0, initial, nil)
		})
		stateA := docA.EncodeStateAsUpdate()
		require.NoError(t, docB.ApplyUpdate(stateA))

		require.Equal(t, initial, textA.ToString())
		require.Equal(t, initial, textB.ToString())

		// Edições concorrentes — ANTES de trocar updates
		docA.Transact(func(txn *crdt.Transaction) {
			textA.Insert(txn, 5, "XXX", nil)
		})
		docB.Transact(func(txn *crdt.Transaction) {
			textB.Insert(txn, 3, "YYY", nil)
		})

		// Troca de updates
		updateA := docA.EncodeStateAsUpdate()
		updateB := docB.EncodeStateAsUpdate()
		require.NoError(t, docA.ApplyUpdate(updateB))
		require.NoError(t, docB.ApplyUpdate(updateA))

		resultA := textA.ToString()
		resultB := textB.ToString()

		assert.Equal(t, resultA, resultB,
			"CRDT divergiu:\n  docA=%q\n  docB=%q", resultA, resultB)
		assert.Equal(t, 1, crdtCount(resultA, "XXX"), "XXX duplicado: %q", resultA)
		assert.Equal(t, 1, crdtCount(resultA, "YYY"), "YYY duplicado: %q", resultA)
		t.Logf("✅ Resultado convergido: %q", resultA)
	})

	t.Run("fuzz_30_concurrent_inserts", func(t *testing.T) {
		const iterations = 30
		for i := range iterations {
			docA := crdt.New(crdt.WithGC(false))
			docB := crdt.New(crdt.WithGC(false))

			textA := docA.GetText("content")
			textB := docB.GetText("content")

			const initial = "abcdefghijklmnopqrstuvwxyz"
			docA.Transact(func(txn *crdt.Transaction) {
				textA.Insert(txn, 0, initial, nil)
			})
			stateA := docA.EncodeStateAsUpdate()
			require.NoError(t, docB.ApplyUpdate(stateA), "iter %d: sync inicial", i)

			length := textA.Len()
			posA := rand.IntN(length + 1)
			posB := rand.IntN(length + 1)

			docA.Transact(func(txn *crdt.Transaction) {
				textA.Insert(txn, posA, "XXX", nil)
			})
			docB.Transact(func(txn *crdt.Transaction) {
				textB.Insert(txn, posB, "YYY", nil)
			})

			updateA := docA.EncodeStateAsUpdate()
			updateB := docB.EncodeStateAsUpdate()
			require.NoError(t, docA.ApplyUpdate(updateB), "iter %d: docA←B", i)
			require.NoError(t, docB.ApplyUpdate(updateA), "iter %d: docB←A", i)

			resultA := textA.ToString()
			resultB := textB.ToString()

			if !assert.Equal(t, resultA, resultB,
				"iter %d: CRDT divergiu posA=%d posB=%d\n  docA=%q\n  docB=%q",
				i, posA, posB, resultA, resultB) {
				t.FailNow()
			}
			assert.Equal(t, 1, crdtCount(resultA, "XXX"), "iter %d: XXX duplicado", i)
			assert.Equal(t, 1, crdtCount(resultA, "YYY"), "iter %d: YYY duplicado", i)
		}
		t.Logf("✅ %d iterações de fuzzing passaram", iterations)
	})
}

// =============================================================================
// Teste 3 (lado Go) — Fixture binário para interop com Dart
// =============================================================================

func TestCRDT3_GenerateGoFixture(t *testing.T) {
	docA := crdt.New(crdt.WithGC(false))
	textA := docA.GetText("content")

	docA.Transact(func(txn *crdt.Transaction) {
		textA.Insert(txn, 0, "hello world", nil)
	})
	docA.Transact(func(txn *crdt.Transaction) {
		textA.Insert(txn, 5, "GO_EDIT", nil)
	})

	update := docA.EncodeStateAsUpdate()

	// Self-check
	docB := crdt.New(crdt.WithGC(false))
	textB := docB.GetText("content")
	require.NoError(t, docB.ApplyUpdate(update))
	const expected = "helloGO_EDIT world"
	assert.Equal(t, expected, textB.ToString())

	require.NoError(t, crdtWriteFixture("testdata/crdt3_go_update.bin", update))
	require.NoError(t, crdtWriteFixture("testdata/crdt3_go_expected.txt", []byte(expected)))
	t.Logf("✅ Fixture Go gerado: %d bytes, texto: %q", len(update), expected)
}

func TestCRDT3_ApplyDartUpdate(t *testing.T) {
	data, err := os.ReadFile("testdata/crdt3_dart_update.bin")
	if err != nil {
		t.Skipf("Fixture Dart não encontrado — rode o Teste 2 Dart primeiro: %v", err)
	}
	expected, err := os.ReadFile("testdata/crdt3_dart_expected.txt")
	if err != nil {
		t.Skipf("Expected text não encontrado: %v", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	doc.GetText("content")
	require.NoError(t, doc.ApplyUpdate(data), "Go falhou ao aplicar update Dart")

	// Re-read after apply (GetText outside transact is fine for read)
	got := doc.GetText("content").ToString()
	assert.Equal(t, string(expected), got,
		"Go não reconheceu o update Dart:\n  expected=%q\n  got=%q", string(expected), got)
	t.Logf("✅ Update Dart aplicado no Go: %q", got)
}

// =============================================================================
// helpers
// =============================================================================

func crdtCount(s, sub string) int {
	count := 0
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			count++
			i += len(sub) - 1
		}
	}
	return count
}

func crdtWriteFixture(path string, data []byte) error {
	if err := os.MkdirAll("testdata", 0o755); err != nil {
		return fmt.Errorf("mkdir testdata: %w", err)
	}
	return os.WriteFile(path, data, 0o644)
}
