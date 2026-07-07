# Spec: CRDT LF Validation (Etapa 1 & 2)

This specification defines the validation design for testing the third-party Dart CRDT package `crdt_lf` under fuzzing and deterministic concurrent edge cases before introducing it to the production roadmap.

---

## 1. Objectives

Verify the following properties of `crdt_lf`'s text-collaboration handlers (specifically the Fugue implementation):
1. **Convergence**: Any application order (including out-of-order and duplicated delivery) converges to the exact same document state.
2. **Anti-interleaving**: Concurrent inserts at the same position by different clients maintain word contiguity.
3. **Idempotency**: At-least-once delivery (multiple applications of the same change) does not duplicate or corrupt text.
4. **Causal Snapshotting & Compacted Merge**: A late client reconnecting with operations based on a version prior to a snapshot/compaction still merges cleanly and converges.
5. **No Aliasing/State Leaks**: The package internal representations do not share mutable references that would cause state pollution across concurrent client instances.

---

## 2. Test Suite Architecture (Approach B)

We will isolate the validation code within the main Flutter package by using `dev_dependencies` and a dedicated test directory:

1. **Dependency Integration**:
   - Add `crdt_lf: ^3.2.1` to the root `pubspec.yaml` under `dev_dependencies`.
2. **Directory & File Layout**:
   - Create a test file at `test/crdt_validation/crdt_convergence_test.dart`.
3. **Test Command**:
   - Run tests using `flutter test test/crdt_validation/crdt_convergence_test.dart`.

---

## 3. Pre-Test Audit Protocol (Source Code Inspection)

Before running or writing tests, we must inspect the source code of the `crdt_lf` package to answer:
1. **Aliasing**: Are internal structures (e.g. `Change`, `Op`, nodes in tree/DAG representation) shared by reference between peers or mutable across handler instances? Since Dart runs single-threaded per isolate, aliasing will cause deterministic state mutation bugs rather than classic multi-threaded races.
2. **Out-of-Order Causal Delivery**: How does the package resolve/buffer child operations that arrive before their parent or happens-before causal operations? Does it expect the caller to sequence them, or does it handle buffering internally?

---

## 4. Test Harness & Test Cases Design

### Fuzzing Harness
- **Topology**: 4 independent client documents initialized with a base text.
- **Concurrent Operations**: Each client produces random edits (inserts/deletes) concurrently.
- **Delivery Simulation**: All generated operations are shuffled randomly.
- **Duplication & Shuffle**: Simulate unreliable delivery by duplicating changes and applying them in different shuffled orders on each peer.
- **Reproducibility**:
  - Log the exact `seed` used for the `Random` generator.
  - If a validation test fails, fail with: `Divergência na iteração $iteration, seed=$seed, ops=$allOps` where `ops` details the sequence of generated ops.

### Deterministic Edge Cases

#### 1. Anti-interleaving (Fugue Core Property)
- **Base**: `"Hello"`
- **Client A**: Inserts `" Ola"` at index 5.
- **Client B**: Inserts `" World"` at index 5.
- **Check**: Final merged state must contain either `"Hello Ola World"` or `"Hello World Ola"`, never interleaved characters.

#### 2. Concurrent Overlapping Deletes (True Overlap)
- **Base**: `"The quick brown fox jumps over the lazy dog"`
- **Client A**: Deletes indices 4 to 16 (`"quick brown "`).
- **Client B**: Deletes indices 10 to 20 (`"brown fox ju"`).
- **Check**: The overlapping characters are deleted correctly once, and the remaining document segments join together cleanly.

#### 3. Idempotency (At-least-once)
- Apply the same operation twice to the same client.
- Ensure the state does not duplicate or corrupt.

#### 4. Out-of-Order Causal Delivery
- Deliver child operations before their parent operations (based on the HLC order / DAG frontiers).
- Confirm that the document doesn't corrupt.

#### 5. Late Client Reconnection & Snapshot Continuity
- Clients A and B are synced at version V.
- Client C disconnects.
- A and B perform edits up to V+50, then compact their history into a snapshot.
- Client C reconnects and sends operations based on version V.
- Verify that A/B and C can merge and converge.

---

## 5. Exit Criteria (GO / REAVALIAR)

- **GO**: 1000+ iterations converging, all deterministic edge-case tests (anti-interleaving, overlapping deletes, idempotency, causal out-of-order, snapshot continuity) pass.
- **REAVALIAR**: Any convergence failure, assertion error, or state pollution/aliasing bug.
