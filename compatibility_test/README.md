# Yjs Cross-Compatibility Test Suite

This suite validates bilateral cross-compatibility and convergence between **Dart** (`yjs_dart`) and **Go** (`github.com/reearth/ygo/crdt`).

Both clients must be capable of decoding and applying each other's binary updates, snapshots, and undo/redo operations, converging to the exact same text, map, and array structures under various networking conditions.

---

## Architecture

The test suite is structured as follows:

```text
compatibility_test/
├── cases/              # Test case definitions & shared binary fixtures
│   ├── 01_basic_interop/
│   │   ├── steps.json       # Schema-based operations to execute
│   │   ├── expected.json    # Final target states after execution
│   │   └── fixtures/        # Binary updates (.bin) and snapshots (.snap)
│   ├── ... (25 cases)
│   └── steps.json      # Listing of all case dirs (index)
│
├── dart_runner/        # Dart runner project
│   ├── bin/runner.dart      # Dart steps interpreter
│   ├── bin/fuzzer.dart      # 10,000 iterations stress-fuzzer
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

## Coverage (25 Test Cases)

1. **`01_basic_interop`**: Bilateral basic insertion and verification.
2. **`02_cross_language_roundtrip`**: Edit roundtrip from A to B and back.
3. **`03_convergence_shuffle`**: 4 documents with concurrent ops and shuffled update delivery.
4. **`04_out_of_order`**: Out-of-order update delivery (u4, u2, u5, u1, u3).
5. **`05_duplicate_delivery`**: Duplicate update delivery (u1, u2, u2, u3, u1, u3).
6. **`06_random_duplicate`**: Fuzzing updates with 30% duplicate delivery.
7. **`07_random_network`**: Delays, shuffles, and duplicates.
8. **`08_anti_interleaving`**: Anti-interleaving concurrent inserts.
9. **`09_adjacent_delete`**: Adjacent concurrent deletes.
10. **`10_overlapping_delete`**: Overlapping concurrent deletes.
11. **`11_random_deletes`**: Concurrent random deletes.
12. **`12_random_inserts`**: Concurrent random inserts.
13. **`13_insert_delete_mix`**: Mix of concurrent inserts and deletes.
14. **`14_state_vector`**: State vector incremental sync.
15. **`15_state_vector_fuzz`**: State vector periodic sync.
16. **`16_snapshot`**: Basic snapshot restore.
17. **`17_snapshot_peer_offline`**: Offline peer snapshot/merge.
18. **`18_large_document`**: 100k characters document with 1000 operations.
19. **`19_utf8`**: Emojis, accents, Arabic (RTL), and Chinese characters.
20. **`20_persistence`**: Backup update write and load.
21. **`21_undo`**: Undo/Redo manager integration.
22. **`22_map`**: Concurrent map sets.
23. **`23_array`**: Concurrent array inserts.
24. **`24_nested_structures`**: Map -> Array -> Text nesting.
25. **`25_fuzzing_completo`**: Full integration fuzzing scenario.

---

## Standalone Fuzzing Engine

The suite includes a standalone fuzzer that runs **10,000 stress-testing iterations** of mutations, delays, deletions, state vectors, snapshots, and duplicate packet delivery on 2 to 8 concurrent clients.

To run the fuzzer manually:
```bash
cd dart_runner
dart run bin/fuzzer.dart
```

### Reproducibility
The fuzzer is designed for 100% reproducibility. If a divergence is found, it will dump the random seed and the exact chronological sequence of client operations and network delivery shuffles. You can reproduce the exact failure by setting the `FUZZ_SEED` environment variable:
```bash
set FUZZ_SEED=1783448433555
dart run bin/fuzzer.dart
```

---

## Running the Verification Suite

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
1. **Dart generates** binary updates and writes expected JSON state for all 25 cases.
2. **Go verifies** by reading Dart's updates, applying them, and asserting it converges to Dart's expected states.
3. **Go generates** binary updates and writes expected JSON state.
4. **Dart verifies** by reading Go's updates, applying them, and asserting it converges to Go's expected states.
5. **Runs the 10,000 iterations fuzzer** to stress-test local and peer convergence.

### 2. Manual Commands

**Dart Runner**:
```bash
cd dart_runner
# Generate expected states & binary updates
dart run bin/runner.dart --mode=generate

# Verify current state matches existing expected.json
dart run bin/runner.dart --mode=verify
```

**Go Runner**:
```bash
cd go_runner
# Generate expected states & binary updates
go run main.go --mode=generate

# Verify current state matches existing expected.json
go run main.go --mode=verify
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
