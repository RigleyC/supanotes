# Design Spec - Migration to `dart_crdt`

This document specifies the architecture, trade-offs, and implementation design for migrating the SupaNotes Flutter application from the custom `yjs_dart` local fork to the stable, fully-tested, and officially maintained `dart_crdt` package on pub.dev.

---

## User Review Required

> [!IMPORTANT]
> The server-side synchronization protocol (Go Yjs Relay) uses Yjs binary updates (V1). Since `dart_crdt` implements the identical Y-CRDT binary protocol, network packets will remain completely compatible. No changes are required on the Go backend server.

---

## Proposed Changes

### 1. Dependency Cleanup (`pubspec.yaml`)
* **Remove**: The local package folder [packages/yjs_dart](file:///c:/Users/rigleyc/projects/supanotes/packages/yjs_dart) will be completely deleted from the monorepo.
* **Update**: In [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml):
  * Remove `dependency_overrides` pointing to `yjs_dart`.
  * Add the stable package:
    ```yaml
    dependencies:
      dart_crdt: ^0.3.0
    ```

### 2. Document Node Codec (`yjs_node_codec.dart`)
* Refactor [yjs_node_codec.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/yjs_node_codec.dart):
  * Replace all `yjs_dart` imports with `package:dart_crdt/dart_crdt.dart`.
  * Map `Doc.getMap('nodes')` to the `dart_crdt` Map equivalent.
  * Extract text values using the correct `Text` SharedType and the `.toPlainText()` method.

### 3. Editor Bridge (`yjs_doc_editor_bridge.dart`)
* Refactor [yjs_doc_editor_bridge.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/yjs_doc_editor_bridge.dart):
  * Update mutation callbacks to use standard `dart_crdt` signatures for `Text` insert/delete methods (e.g. `insertText`, `deleteText`).
  * Verify map operations (`nodesMap.setAttr`, `nodesMap.deleteAttr`) and observer callback bindings (`observe`).
  * Ensure transaction execution via `doc.transact(...)` remains correct.

### 4. Sync Manager & WebSocket Client (`yjs_sync_manager.dart` and `yjs_websocket_client.dart`)
* Refactor [yjs_sync_manager.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/yjs_sync_manager.dart):
  * **Simplify**: Completely remove the text-key pre-registration loops in `loadDoc`. Since `dart_crdt` correctly decodes unknown types on update without throwing cast exceptions, this workaround is obsolete.
  * Simplify the snapshot restoration pipeline.
* Refactor [yjs_websocket_client.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/sync/yjs_websocket_client.dart):
  * Map encoder/decoder operations and sync handshake bytes (Step 1, Step 2, updates) using `dart_crdt` sync and state vector tools (`encodeStateVectorFromUpdate`, `diffUpdate`, etc.).

---

## Verification Plan

### Automated Tests
* Run the existing local convergence validation test suite to verify that both sequential and concurrent edits resolve identically and do not regress:
  ```bash
  flutter test test/crdt_validation/crdt_convergence_test.dart --no-pub
  ```
* Run the end-to-end WebSocket integration test to verify real-time convergence against the Go backend:
  ```bash
  flutter test test/crdt_validation/crdt_websocket_test.dart --no-pub
  ```
