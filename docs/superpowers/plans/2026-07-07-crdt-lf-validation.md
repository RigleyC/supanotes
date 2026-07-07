# Plan: CRDT LF Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a fuzzing harness and deterministic test suite to validate the convergence, idempotency, anti-interleaving, and snapshot continuity properties of the `crdt_lf` package.

**Architecture:** We will add `crdt_lf` to `dev_dependencies` of our Flutter app, locate and audit the third-party source code to identify aliasing/causal delivery assumptions, and implement tests in `test/crdt_validation/crdt_convergence_test.dart` with a deterministic, seed-based reproducibility harness.

**Tech Stack:** Dart, Flutter, `crdt_lf` package, and `flutter_test`.

---

### Task 1: Dependency Integration

**Files:**
- Modify: [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml)

- [ ] **Step 1: Add crdt_lf to dev_dependencies**
  Insert the dependency `crdt_lf: ^3.2.1` in the `dev_dependencies` block of `pubspec.yaml`.
  
  Code to add:
  ```yaml
  dev_dependencies:
    # ... other dependencies ...
    crdt_lf: ^3.2.1
  ```

- [ ] **Step 2: Run pub get**
  Run the command to install the new dependency:
  `flutter pub get`
  Expected: Command completes successfully with exit code 0.

- [ ] **Step 3: Commit**
  Run:
  `git add pubspec.yaml pubspec.lock; git commit -m "chore(sync): add crdt_lf to dev_dependencies"`

---

### Task 2: Pre-Test Source Code Audit

**Files:**
- Create: [crdt_audit_notes.md](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_audit_notes.md)

- [ ] **Step 1: Locate the crdt_lf package cache**
  Run a command to list the pub cache path for the downloaded `crdt_lf` package or check where it has been extracted on the system.
  Expected: We find the folder (e.g. under `AppData\Local\Pub\Cache\hosted\pub.dev\crdt_lf-3.2.1`).

- [ ] **Step 2: Inspect CRDTFugueTextHandler and nodes for aliasing**
  Open the handler file `lib/src/handler/crdt_fugue_text_handler.dart` and the internal text/list data structure representation files (such as `fugue` tree/DAG nodes). Check if list operations or changes reuse mutable objects or share state references between instances without performing proper deep copies.

- [ ] **Step 3: Check causal ordering expectations**
  Inspect how `importChanges` or `apply` handles causal ordering. Check if operations must arrive strictly in causal order (based on the HLC parentage/frontiers) or if out-of-order operations are buffered automatically in a DAG/buffer list.

- [ ] **Step 4: Record findings in audit notes**
  Create the `test/crdt_validation/crdt_audit_notes.md` file and document the findings on reference reuse and causal order processing.

- [ ] **Step 5: Commit findings**
  Run:
  `git add test/crdt_validation/crdt_audit_notes.md; git commit -m "docs(sync): add crdt_lf source code audit findings"`

---

### Task 3: Fuzzing Harness & Convergence Testing

**Files:**
- Create: [crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Implement the basic test skeleton with random seed reproducibility**
  Create `test/crdt_validation/crdt_convergence_test.dart` containing the main fuzzing test with seed logging and randomized operations generator.

  Code:
  ```dart
  import 'dart:math';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:crdt_lf/crdt_lf.dart';

  void main() {
    test('crdt_lf fuzzing convergence under shuffled and duplicated delivery', () {
      final seed = DateTime.now().millisecondsSinceEpoch;
      final rand = Random(seed);
      print('[Fuzz] Running with seed: $seed');

      for (var iteration = 0; iteration < 1000; iteration++) {
        final base = "O rato roeu a roupa do rei de Roma.";
        
        // Setup 4 client docs
        final docs = List.generate(4, (i) {
          final peerId = PeerId.parse('00000000-0000-0000-0000-00000000000${i}');
          final doc = CRDTDocument(peerId: peerId)..registerDefaultFactories();
          // Initialize a Fugue text handler on each doc
          final handler = CRDTFugueTextHandler(doc, 'text-fuzz');
          handler.insert(0, base);
          return doc;
        });

        // Run local concurrent operations on each doc
        final List<Change> allChanges = [];
        for (var i = 0; i < docs.length; i++) {
          final doc = docs[i];
          final textHandler = doc.registeredHandlers['text-fuzz']! as CRDTFugueTextHandler;
          
          final opCount = rand.nextInt(5) + 1;
          for (var j = 0; j < opCount; j++) {
            // Pick random position to insert or delete
            final currentLen = textHandler.value.length;
            if (currentLen > 0 && rand.nextBool()) {
              // Delete
              final pos = rand.nextInt(currentLen);
              final count = rand.nextInt(min(5, currentLen - pos)) + 1;
              textHandler.delete(pos, count);
            } else {
              // Insert
              final pos = rand.nextInt(currentLen + 1);
              final text = String.fromCharCodes(
                List.generate(rand.nextInt(5) + 1, (_) => rand.nextInt(26) + 97)
              );
              textHandler.insert(pos, text);
            }
          }
          // Export changes generated by this client
          allChanges.addAll(doc.exportChanges());
        }

        // Simulate network delivery: shuffle changes
        allChanges.shuffle(rand);

        // Apply changes to each document in different orders (shuffled per document)
        for (final doc in docs) {
          final docChanges = List<Change>.from(allChanges)..shuffle(rand);
          // Apply changes twice to simulate duplicate delivery (idempotency check)
          for (final change in docChanges) {
            doc.importChanges([change]);
            doc.importChanges([change]); // Duplicate application
          }
        }

        // Compare final text states
        final finalStates = docs.map((d) {
          final textHandler = d.registeredHandlers['text-fuzz']! as CRDTFugueTextHandler;
          return textHandler.value;
        }).toSet();

        if (finalStates.length != 1) {
          fail('Divergence in iteration $iteration! Seed = $seed.\nStates: $finalStates');
        }
      }
    });
  }
  ```

- [ ] **Step 2: Run fuzzing test**
  Run:
  `flutter test test/crdt_validation/crdt_convergence_test.dart`
  Expected: Test passes successfully.

- [ ] **Step 3: Commit**
  Run:
  `git add test/crdt_validation/crdt_convergence_test.dart; git commit -m "test(sync): implement crdt_lf fuzzing convergence test"`

---

### Task 4: Deterministic Core Edge Cases

**Files:**
- Modify: [crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Append anti-interleaving, overlapping deletes, and idempotency tests**
  Add the deterministic test cases for anti-interleaving, concurrent overlapping deletes, and idempotency.

  Code to append to `test/crdt_validation/crdt_convergence_test.dart`:
  ```dart
  group('crdt_lf - Deterministic Edge Cases', () {
    test('Anti-interleaving (Fugue Core)', () {
      final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000001'))..registerDefaultFactories();
      final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000002'))..registerDefaultFactories();

      final textA = CRDTFugueTextHandler(docA, 'text-anti');
      textA.insert(0, "Hello");

      // Sync base
      docB.importChanges(docA.exportChanges());
      final textB = docB.registeredHandlers['text-anti']! as CRDTFugueTextHandler;

      // Concurrent insertions at index 5
      textA.insert(5, " Ola");
      textB.insert(5, " World");

      // Merge changes
      final changesA = docA.exportChanges();
      final changesB = docB.exportChanges();

      docA.importChanges(changesB);
      docB.importChanges(changesA);

      expect(textA.value, textB.value);
      final finalVal = textA.value;
      // Should not be interleaved, words must remain contiguous
      expect(
        finalVal == "Hello Ola World" || finalVal == "Hello World Ola",
        true,
        reason: 'Interleaved result detected: $finalVal',
      );
    });

    test('Concurrent Overlapping Deletes', () {
      final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000001'))..registerDefaultFactories();
      final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000002'))..registerDefaultFactories();

      final textA = CRDTFugueTextHandler(docA, 'text-delete');
      textA.insert(0, "The quick brown fox jumps over the lazy dog");

      // Sync base
      docB.importChanges(docA.exportChanges());
      final textB = docB.registeredHandlers['text-delete']! as CRDTFugueTextHandler;

      // Client A deletes indices 4 to 16 ("quick brown ")
      textA.delete(4, 12);

      // Client B deletes indices 10 to 20 ("brown fox ju")
      // Indices relative to the base text: index 10 is 'b', count 10 is "brown fox " + "ju"
      textB.delete(10, 10);

      // Merge changes
      final changesA = docA.exportChanges();
      final changesB = docB.exportChanges();

      docA.importChanges(changesB);
      docB.importChanges(changesA);

      expect(textA.value, textB.value);
      // Expected result: "The fox jumps over the lazy dog" but without "fox ju", so "The mps over the lazy dog"
      // Let's verify convergence between both documents
      expect(textA.value.isNotEmpty, true);
    });

    test('Idempotency / Double Application', () {
      final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000001'))..registerDefaultFactories();
      final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000002'))..registerDefaultFactories();

      final textA = CRDTFugueTextHandler(docA, 'text-idem');
      textA.insert(0, "Base");

      docB.importChanges(docA.exportChanges());
      final textB = docB.registeredHandlers['text-idem']! as CRDTFugueTextHandler;

      textA.insert(4, " Edit");
      final changes = docA.exportChanges();

      // Apply changes twice to B
      docB.importChanges(changes);
      docB.importChanges(changes);

      expect(textB.value, "Base Edit");
    });
  });
  ```

- [ ] **Step 2: Run deterministic tests**
  Run:
  `flutter test test/crdt_validation/crdt_convergence_test.dart`
  Expected: All tests pass.

- [ ] **Step 3: Commit**
  Run:
  `git add test/crdt_validation/crdt_convergence_test.dart; git commit -m "test(sync): add deterministic test cases for anti-interleaving, deletes and idempotency"`

---

### Task 5: Out-of-Order Causal Delivery & Snapshot Continuity

**Files:**
- Modify: [crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Append out-of-order causal and snapshot continuity tests**
  Add the final test cases checking causal out-of-order buffering and peer reconnection after snapshot compaction.

  Code to append to `test/crdt_validation/crdt_convergence_test.dart`:
  ```dart
  group('crdt_lf - Causal Delivery & Snapshots', () {
    test('Out-of-order causal delivery', () {
      final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000001'))..registerDefaultFactories();
      final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000002'))..registerDefaultFactories();

      final textA = CRDTFugueTextHandler(docA, 'text-ooo');
      textA.insert(0, "A"); // Parent operation

      final changes1 = docA.exportChanges();

      textA.insert(1, "B"); // Child operation (causally depends on changes1)
      final changes2 = docA.exportChanges();

      // Deliver changes2 (child) BEFORE changes1 (parent) to Doc B
      try {
        docB.importChanges(changes2);
      } catch (e) {
        // If the library throws when dependencies are missing, that's acceptable,
        // but we must check if we can resolve it once changes1 arrives.
        print('[OOO Test] importChanges threw error on missing parent dependency: $e');
      }

      // Deliver parent
      docB.importChanges(changes1);
      
      // Re-apply/ensure child is resolved
      docB.importChanges(changes2);

      final textB = docB.registeredHandlers['text-ooo']! as CRDTFugueTextHandler;
      expect(textB.value, "AB");
    });

    test('Late peer reconnection & snapshot continuity', () {
      final docA = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000001'))..registerDefaultFactories();
      final docB = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000002'))..registerDefaultFactories();
      final docC = CRDTDocument(peerId: PeerId.parse('00000000-0000-0000-0000-000000000003'))..registerDefaultFactories();

      final textA = CRDTFugueTextHandler(docA, 'text-snap');
      textA.insert(0, "Hello");

      // Sync all to version V
      final initialChanges = docA.exportChanges();
      docB.importChanges(initialChanges);
      docC.importChanges(initialChanges);

      // Client C goes offline.
      // A and B perform edits up to V+50
      final textB = docB.registeredHandlers['text-snap']! as CRDTFugueTextHandler;
      for (var i = 0; i < 50; i++) {
        textA.insert(textA.value.length, ".");
        docB.importChanges(docA.exportChanges());
      }

      // Compact A/B history into snapshot
      final snapshot = docB.takeSnapshot();
      // Reconstruct docB from snapshot to prune local operations history
      final docBCompacted = CRDTDocument(peerId: docB.peerId)..registerDefaultFactories();
      docBCompacted.importSnapshot(snapshot);
      docBCompacted.reconstruct();
      final textBCompacted = docBCompacted.registeredHandlers['text-snap']! as CRDTFugueTextHandler;

      // C wakes up and makes edits based on version V
      final textC = docC.registeredHandlers['text-snap']! as CRDTFugueTextHandler;
      textC.insert(5, " C");

      // C sends edits to the compacted B
      final changesC = docC.exportChanges();
      docBCompacted.importChanges(changesC);

      // Compacted B sends snapshot & edits to C
      docC.importSnapshot(snapshot);
      docC.reconstruct();

      expect(textBCompacted.value, textC.value);
    });
  });
  ```

- [ ] **Step 2: Run all tests**
  Run:
  `flutter test test/crdt_validation/crdt_convergence_test.dart`
  Expected: All tests pass.

- [ ] **Step 3: Commit**
  Run:
  `git add test/crdt_validation/crdt_convergence_test.dart; git commit -m "test(sync): add causal delivery and snapshot continuity tests"`
