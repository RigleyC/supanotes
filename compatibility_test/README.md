# Yjs Cross-Compatibility Test Suite

This suite validates bilateral cross-compatibility and convergence between **Dart** (`yjs_dart`) and **Go** (`github.com/reearth/ygo/crdt`).

Both clients must be capable of decoding and applying each other's binary updates and snapshots, converging to the exact same text, map, and array structures under various networking conditions.

---

## Architecture

The test suite is structured as follows:

```text
compatibility_test/
├── cases/              # Test case definitions & shared binary fixtures
│   ├── 01_basic_insert/
│   │   ├── steps.json       # Schema-based operations to execute
│   │   ├── expected.json    # Final target states after execution
│   │   └── fixtures/        # Binary updates (.bin) and snapshots (.snap)
│   ├── ... (15 cases)
│   └── steps.json      # Listing of all case dirs (index)
│
├── dart_runner/        # Dart runner project
│   ├── bin/runner.dart      # Dart steps interpreter
│   └── pubspec.yaml
│
├── go_runner/          # Go runner project
│   ├── main.go              # Go steps interpreter
│   └── go.mod
│
├── validate.bat        # Automated validation pipeline (Windows)
└── validate.sh         # Automated validation pipeline (Unix/CI)
```

---

## Coverage (15 Test Cases)

1. **`01_basic_insert`**: Simple single-character and block insertions.
2. **`02_go_to_dart`**: Simple updates transfer from Go to Dart.
3. **`03_out_of_order`**: Causal dependencies (applying update `B` before `A` and checking integration once `A` arrives).
4. **`04_duplicate`**: Idempotency check when applying the same update multiple times.
5. **`05_state_vector`**: Exchanging state vectors and exporting minimal sync updates.
6. **`06_snapshot`**: Capturing snapshots, deleting history, and restoring older states.
7. **`07_anti_interleaving`**: Interleaved concurrent insertions resolved deterministically (Fugue-like ordering check).
8. **`08_overlapping_deletes`**: Genuinely overlapping concurrent deletions on the same text indices.
9. **`09_map`**: Shared `YMap` operations (setting keys, nested maps, and arrays).
10. **`10_array`**: Shared `YArray` operations (insertions, deletions, and nested elements).
11. **`11_large_doc`**: Large document simulation (multiple structural layers).
12. **`12_fuzzing`**: Chaos simulation with concurrent mutations, update shuffling, and packet duplication.
13. **`13_persistence`**: Document state persistence and offline/online merge verification.
14. **`14_incremental`**: Incremental state updates applied sequentially on top of each other.
15. **`15_supanotes_markdown`**: Complex concurrent editing simulating real-world markdown note collaborative edits.

---

## Running the Suite

### 1. Automated Pipeline (Recommended)

Run the cross-verification script from this folder:

**Windows**:
```cmd
validate.bat
```

**Unix/macOS/CI**:
```bash
chmod +x validate.sh
./validate.sh
```

This performs the following steps:
1. **Dart generates** binary updates and writes expected JSON state for all 15 cases.
2. **Go verifies** by reading Dart's updates, applying them, and asserting it converges to Dart's expected states.
3. **Go generates** binary updates and writes expected JSON state.
4. **Dart verifies** by reading Go's updates, applying them, and asserting it converges to Go's expected states.

### 2. Manual Commands

**Dart Runner**:
```bash
cd dart_runner
# Generate expected states & binary updates
dart run bin/runner.dart --mode=generate

# Verify current state matches existing expected.json
dart run bin/runner.dart --mode=verify

# Run a specific test case
dart run bin/runner.dart --mode=verify --case=08_overlapping_deletes
```

**Go Runner**:
```bash
cd go_runner
# Generate expected states & binary updates
go run main.go --mode=generate

# Verify current state matches existing expected.json
go run main.go --mode=verify

# Run a specific test case
go run main.go --mode=verify --case=08_overlapping_deletes
```

---

## Library Bug Overrides

During this spike, a critical bug was discovered in the `yjs_dart` package version `1.1.15`:
* **The Bug**: The internal `_ContentStringStub`'s `splice` method (used during item splits on remote updates) returned a split substring, but failed to truncate the original string in the left item. This resulted in corrupted text with duplicated suffixes on remote deletes.
* **The Fix**: Because we cannot easily modify code inside the Pub cache, the Dart runner dynamically overrides the content reference registration at startup:
  ```dart
  contentRefs[4] = (decoder) => ContentString(decoder.readString() as String);
  ```
  This replaces the buggy stub with the correct, fully-implemented `ContentString` class from `content.dart`, resolving all duplicate text issues.
