# dart_crdt Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the SupaNotes Flutter application from the custom `yjs_dart` fork to the stable and officially maintained `dart_crdt` package on pub.dev.

**Architecture:** Replace package references, update client classes (`Doc`, `MapShared`, `Text`), remove the obsolete type pre-registration workaround in the Sync Manager, and ensure identical binary sync protocol behavior to preserve compatibility with the Go backend server.

**Tech Stack:** Dart, Flutter, `dart_crdt: ^0.3.0`

---

### Task 1: Dependency Cleanup and Initial Compilation Check

**Files:**
- Modify: [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml)
- Delete: [packages/yjs_dart](file:///c:/Users/rigleyc/projects/supanotes/packages/yjs_dart) (folder)
- Test: [test/crdt_validation/crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Update dependencies in pubspec.yaml**
Remove `dependency_overrides` for `yjs_dart`, and add `dart_crdt: ^0.3.0` under `dependencies`.

- [ ] **Step 2: Delete packages/yjs_dart folder**
Delete the entire directory `packages/yjs_dart` from disk.

- [ ] **Step 3: Run pub get and verify compiler error locations**
Run: `flutter pub get`
Verify that `yjs_dart` is replaced by `dart_crdt` and compilation errors point to imports in our 6 client files.

- [ ] **Step 4: Commit**
```bash
git add pubspec.yaml
git commit -m "chore(deps): migrate dependency from yjs_dart to dart_crdt"
```

---

### Task 2: Refactor Node Codec (`yjs_node_codec.dart`)

**Files:**
- Modify: [lib/features/notes/domain/yjs_node_codec.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/yjs_node_codec.dart)
- Test: [test/crdt_validation/crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Update imports and Doc methods**
Replace `import 'package:yjs_dart/yjs_dart.dart';` with `import 'package:dart_crdt/dart_crdt.dart';`.
Update `noteNodesFromDoc` to use `dart_crdt` Map shared types:
```dart
List<NoteNode> noteNodesFromDoc(Doc doc, {String? noteIdOverride}) {
  final nodes = <NoteNode>[];
  final nodesMap = doc.getMap('nodes');
  if (nodesMap == null) return nodes;

  for (final key in nodesMap.keys) {
    final raw = nodesMap.getAttr(key);
    if (raw is! String) continue;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      final nodeId = meta['id'] as String;
      final ytext = doc.getText('content/$nodeId');
      final textContent = ytext.toPlainText();
      final data = Map<String, dynamic>.from(meta['data'] as Map? ?? {});
      if (textContent.isNotEmpty) {
        data['text'] = textContent;
      }
      final rawParentId = meta['parentId'] as String?;
      final resolvedParentId =
          (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
      nodes.add(NoteNode(
        id: nodeId,
        noteId: noteIdOverride ?? meta['noteId'] as String? ?? '',
        parentId: resolvedParentId,
        position: meta['position']?.toString() ?? 'a0',
        type: meta['type'] as String? ?? 'paragraph',
        data: jsonEncode(data),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (meta['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (meta['updatedAt'] as num?)?.toInt() ?? 0,
        ),
        isDirty: false,
      ));
    } catch (_) {
      continue;
    }
  }

  nodes.sort((a, b) => a.position.compareTo(b.position));
  return nodes;
}
```

- [ ] **Step 2: Commit**
```bash
git add lib/features/notes/domain/yjs_node_codec.dart
git commit -m "refactor(crdt): update yjs_node_codec to use dart_crdt MapShared and Text"
```

---

### Task 3: Refactor Sync Manager and Remove Obsolete Workarounds

**Files:**
- Modify: [lib/core/sync/yjs_sync_manager.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/yjs_sync_manager.dart)
- Test: [test/crdt_validation/crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Replace imports and remove type pre-registration workaround in loadDoc**
Replace imports. Remove the `for (final node in allNodes)` loop that pre-registered text types. The `loadDoc` method should look clean:
```dart
  Future<Doc> loadDoc(String noteId) async {
    final cached = _docs[noteId];
    if (cached != null) return cached;

    final stateRow = await (_db.select(_db.localYjsStates)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();
    if (stateRow != null) {
      final doc = Doc();
      try {
        applyUpdate(doc, stateRow.state);

        // Merge offline changes from SQLite into YDoc
        final nodesMap = doc.getMap('nodes');
        final allNodes = await (_db.select(_db.noteNodes)
              ..where((t) => t.noteId.equals(noteId)))
            .get();
        bool mutated = false;
        doc.transact((txn) {
          for (final node in allNodes) {
            if (node.deletedAt != null) {
              if (nodesMap.getAttr(node.id) != null) {
                nodesMap.deleteAttr(node.id);
                final ytext = doc.getText('content/${node.id}');
                if (ytext.toPlainText().isNotEmpty) {
                  ytext.deleteText(0, ytext.toPlainText().length);
                }
                mutated = true;
              }
              continue;
            }

            final rawMeta = nodesMap.getAttr(node.id) as String?;
            final dbData = jsonDecode(node.data) as Map<String, dynamic>;
            final dbText = dbData['text'] as String? ?? '';
            final ytext = doc.getText('content/${node.id}');
            final ytextStr = ytext.toPlainText();

            if (rawMeta == null || ytextStr != dbText) {
              final newMeta = {
                'id': node.id,
                'parentId': node.parentId,
                'position': node.position,
                'type': node.type,
                'data': dbData,
                'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
              };
              nodesMap.setAttr(node.id, jsonEncode(newMeta));

              if (ytextStr != dbText) {
                if (ytext.toPlainText().isNotEmpty) {
                  ytext.deleteText(0, ytext.toPlainText().length);
                }
                if (dbText.isNotEmpty) {
                  ytext.insertText(0, dbText);
                }
              }
              mutated = true;
            }
          }
        });

        if (mutated) {
          await _db.into(_db.localYjsStates).insertOnConflictUpdate(
                LocalYjsStatesCompanion(
                  noteId: Value(noteId),
                  state: Value(encodeStateAsUpdate(doc)),
                ),
              );
        }

        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Loaded snapshot for note=$noteId', name: 'YjsSync');
        return doc;
      } catch (e, stackTrace) {
        dev.log('[YjsSyncManager] CRITICAL: Failed to apply snapshot for note=$noteId: $e. Clearing corrupted snapshot.',
            name: 'YjsSync', error: e, stackTrace: stackTrace);
        await (_db.delete(_db.localYjsStates)..where((t) => t.noteId.equals(noteId))).go();
        
        final doc = Doc();
        _docs[noteId] = doc;
        dev.log('[YjsSyncManager] Initialized empty doc for note=$noteId after clearing corrupted snapshot. Waiting for server sync.', name: 'YjsSync');
        return doc;
      }
    }

    final note = await (_db.select(_db.notes)..where((t) => t.id.equals(noteId))).getSingleOrNull();
    if (note != null && note.hasRemoteCopy) {
      final doc = Doc();
      _docs[noteId] = doc;
      dev.log('[YjsSyncManager] Initialized empty doc for existing note=$noteId from server. Waiting for sync.', name: 'YjsSync');
      return doc;
    }

    dev.log('[YjsSyncManager] Reconstruction triggered (new local note) for noteId=$noteId at ${DateTime.now()}', name: 'YjsSync');
    final doc = await _reconstructFromLocal(noteId);
    _docs[noteId] = doc;
    return doc;
  }
```

- [ ] **Step 2: Update _reconstructFromLocal**
Adapt `_reconstructFromLocal` method:
```dart
  Future<Doc> _reconstructFromLocal(String noteId) async {
    final doc = Doc();
    final nodes = await (_db.select(_db.noteNodes)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull()))
        .get();

    final nodesMap = doc.getMap('nodes');
    doc.transact((txn) {
      for (final node in nodes) {
        final dbData = jsonDecode(node.data) as Map<String, dynamic>;
        final dbText = dbData['text'] as String? ?? '';
        final meta = {
          'id': node.id,
          'parentId': node.parentId,
          'position': node.position,
          'type': node.type,
          'data': dbData,
          'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
        };
        nodesMap.setAttr(node.id, jsonEncode(meta));
        if (dbText.isNotEmpty) {
          final ytext = doc.getText('content/${node.id}');
          ytext.insertText(0, dbText);
        }
      }
    });

    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(encodeStateAsUpdate(doc)),
          ),
        );

    return doc;
  }
```

- [ ] **Step 3: Commit**
```bash
git add lib/core/sync/yjs_sync_manager.dart
git commit -m "refactor(crdt): simplify yjs_sync_manager by removing type pre-registration"
```

---

### Task 4: Refactor Editor Bridge (`yjs_doc_editor_bridge.dart`)

**Files:**
- Modify: [lib/features/notes/domain/yjs_doc_editor_bridge.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/yjs_doc_editor_bridge.dart)
- Test: [test/crdt_validation/crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)

- [ ] **Step 1: Refactor observe callback and operations**
Adapt `YjsDocEditorBridge` properties and observer binding:
```dart
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required NoteSyncCoordinator coordinator,
    required void Function(Uint8List update) sendUpdate,
  })  : _doc = doc,
        _coordinator = coordinator,
        _sendUpdate = sendUpdate {
    _nodesSub = _doc.getMap('nodes').observe((event) {
      _onNodesChanged();
    });
    coordinator.onNodeFlush = onLocalFlush;
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  late final void Function() _nodesSub;
  // ...
```

- [ ] **Step 2: Update mutation operations**
Replace `.get(op.nodeId)` with `.getAttr(op.nodeId)`, `.set` with `.setAttr`, and `.delete` with `.deleteAttr` for the `nodesMap`. Replace `ytext.insert` / `ytext.delete` with `ytext.insertText` / `ytext.deleteText`. Ensure the file compiles.

- [ ] **Step 3: Commit**
```bash
git add lib/features/notes/domain/yjs_doc_editor_bridge.dart
git commit -m "refactor(crdt): adapt yjs_doc_editor_bridge to dart_crdt APIs"
```

---

### Task 5: Refactor WebSocket Client, Controller and Sync Service

**Files:**
- Modify: [lib/core/sync/yjs_websocket_client.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/yjs_websocket_client.dart)
- Modify: [lib/core/sync/sync_service.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/sync_service.dart)
- Modify: [lib/features/notes/presentation/controllers/note_editor_controller.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/presentation/controllers/note_editor_controller.dart)
- Test: [test/crdt_validation/crdt_websocket_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_websocket_test.dart)

- [ ] **Step 1: Refactor WebSocket Handshake protocol**
Update imports to `dart_crdt` in all three files. Adapt `yjs_websocket_client.dart` to write Step 1 vector and Step 2 updates:
```dart
  void _sendStep1(Doc doc) {
    // Write Step 1 message using standard Yjs sync protocol:
    // [messageSyncStep1, encodeStateVector(doc)]
    final vector = encodeStateVector(doc);
    final payload = Uint8List(1 + vector.length);
    payload[0] = 0; // messageSyncStep1
    payload.setRange(1, payload.length, vector);
    _sendRaw(payload);
  }

  void _handleMessage(Uint8List data) {
    if (data.isEmpty) return;
    final msgType = data[0];
    final payload = data.sublist(1);
    
    switch (msgType) {
      case 0: // messageSyncStep1
        final update = diffUpdate(_doc, payload);
        final response = Uint8List(1 + update.length);
        response[0] = 1; // messageSyncStep2
        response.setRange(1, response.length, update);
        _sendRaw(response);
        
        if (!_handshakeDone) {
          _handshakeDone = true;
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
        break;
      case 1: // messageSyncStep2
      case 2: // messageSyncUpdate
        applyUpdate(_doc, payload);
        _onUpdateController.add(payload);
        break;
    }
  }
```

- [ ] **Step 2: Commit**
```bash
git add lib/core/sync/yjs_websocket_client.dart lib/core/sync/sync_service.dart lib/features/notes/presentation/controllers/note_editor_controller.dart
git commit -m "refactor(crdt): adapt websocket client and controllers to dart_crdt"
```

---

### Task 6: Run Verification and Test Suites

**Files:**
- Modify: [test/crdt_validation/crdt_convergence_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_convergence_test.dart)
- Modify: [test/crdt_validation/crdt_websocket_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_websocket_test.dart)

- [ ] **Step 1: Update convergence test imports**
Replace `package:yjs_dart/yjs_dart.dart` imports with `package:dart_crdt/dart_crdt.dart` in both test files and make necessary type adjustments (e.g. `ClientId` for `clientId` configuration).

- [ ] **Step 2: Run local convergence tests**
Run: `flutter test test/crdt_validation/crdt_convergence_test.dart --no-pub`
Expected: ALL tests PASS.

- [ ] **Step 3: Run WebSocket integration tests**
Run: `flutter test test/crdt_validation/crdt_websocket_test.dart --no-pub`
Expected: ALL tests PASS.

- [ ] **Step 4: Commit**
```bash
git add test/crdt_validation/crdt_convergence_test.dart test/crdt_validation/crdt_websocket_test.dart
git commit -m "test(crdt): update test suites to use dart_crdt and verify"
```
