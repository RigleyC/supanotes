package crdttest

import (
	"math/rand/v2"
	"testing"

	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A2. Fuzzing específico com nodes mistos (task=YMap, paragraph=YText)
func TestCRDT2_FuzzMixedNodes(t *testing.T) {
	const iterations = 30
	for i := 0; i < iterations; i++ {
		docA := crdt.New(crdt.WithGC(false))
		docB := crdt.New(crdt.WithGC(false))

		// Ambos pegam o array principal "nodes"
		nodesA := docA.GetArray("nodes")
		nodesB := docB.GetArray("nodes")

		// Sync inicial
		docA.Transact(func(txn *crdt.Transaction) {
			nodesA.Insert(txn, 0, []any{"dummy"})
		})
		require.NoError(t, docB.ApplyUpdate(docA.EncodeStateAsUpdate()))

		// Edição concorrente:
		// Cliente A insere uma string
		docA.Transact(func(txn *crdt.Transaction) {
			nodesA.Insert(txn, 1, []any{"paragraph text"})
		})

		// Cliente B insere um map
		docB.Transact(func(txn *crdt.Transaction) {
			nodesB.Insert(txn, 1, []any{map[string]any{"completed": false, "text": "task text"}})
		})

		// Troca de updates
		updateA := docA.EncodeStateAsUpdate()
		updateB := docB.EncodeStateAsUpdate()

		errA := docA.ApplyUpdate(updateB)
		errB := docB.ApplyUpdate(updateA)

		require.NoError(t, errA, "iter %d: docA←B", i)
		require.NoError(t, errB, "iter %d: docB←A", i)

		// Os arrays devem ter convergido (tamanho 3, pois ambos inseriram)
		assert.Equal(t, 3, nodesA.Len())
		assert.Equal(t, 3, nodesB.Len())
		
		// Serializar ambos e comparar
		stateA := docA.EncodeStateAsUpdate()
		stateB := docB.EncodeStateAsUpdate()
		assert.Equal(t, stateA, stateB, "States diverged on iter %d", i)
	}
	t.Logf("✅ %d iteracoes de fuzzing de nós mistos passaram", iterations)
}

// A1 extra: insert + delete
func TestCRDT1_FuzzInsertDelete(t *testing.T) {
	const iterations = 50
	for i := 0; i < iterations; i++ {
		docA := crdt.New(crdt.WithGC(false))
		docB := crdt.New(crdt.WithGC(false))

		textA := docA.GetText("content")
		textB := docB.GetText("content")

		// Insert inicial
		docA.Transact(func(txn *crdt.Transaction) {
			textA.Insert(txn, 0, "1234567890", nil)
		})
		require.NoError(t, docB.ApplyUpdate(docA.EncodeStateAsUpdate()))

		length := textA.Len()
		posA := rand.IntN(length)
		posB := rand.IntN(length)

		// A insere, B deleta
		docA.Transact(func(txn *crdt.Transaction) {
			textA.Insert(txn, posA, "INS", nil)
		})
		docB.Transact(func(txn *crdt.Transaction) {
			textB.Delete(txn, posB, 1)
		})

		updateA := docA.EncodeStateAsUpdate()
		updateB := docB.EncodeStateAsUpdate()
		
		require.NoError(t, docA.ApplyUpdate(updateB))
		require.NoError(t, docB.ApplyUpdate(updateA))

		resultA := textA.ToString()
		resultB := textB.ToString()
		
		assert.Equal(t, resultA, resultB, "CRDT diverge: A=%q, B=%q", resultA, resultB)
	}
}
