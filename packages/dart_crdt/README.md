<p align="center">
<img src="assets/logo.png" alt="dart_crdt logo" width="160" height="160">
</p>
<h1 align="center">dart_crdt</h1>
<hr>

<p align="center">
<a href="https://github.com/salakar/ycrdt/blob/main/COVERAGE.md">Coverage: 95.21%</a>
</p>

## Overview

A pure Dart CRDT package for local-first collaborative data structures.

`dart_crdt` provides document state, shared collection/text types, binary update
encoding, relative positions, snapshots, undo/redo, attribution metadata, and
compatibility-oriented fixtures for VM, Flutter, and web runtimes.

## Supported Features

| Area | Support |
| --- | --- |
| Documents | Client IDs, transactions, roots, observers, lifecycle events, and subdocuments. |
| Presence | Awareness state, local presence fields, update exchange, and offline removals. |
| Shared types | Arrays, maps, text, XML-like trees, nested types, embeds, and attributes. |
| Sync | Deterministic V1/V2 updates, state vectors, merge/diff helpers, update conversion, and update application. |
| Editing | Rich-text deltas, snapshots, relative positions, undo/redo, and attribution metadata. |
| Validation | Serialized fixtures, malformed-input fuzzing, coverage gates, benchmarks, and compiled web checks. |

## Install

```yaml
dependencies:
  dart_crdt: ^0.2.0
```

```dart
import 'package:dart_crdt/dart_crdt.dart';
```

## Quick Start

Create a document and mutate a shared text type:

```dart
final doc = Doc();
final text = doc.getText('body');

text.insertText(0, 'Hello, local-first Dart.');

print(text.toPlainText()); // Hello, local-first Dart.
```

Shared arrays, maps, text, XML fragments/elements/text, and nested shared types
are available through `SharedType` APIs.

```dart
final list = doc.getArray('items');
list.push('one');
list.push(SharedType(kind: SharedTypeKind.map, name: 'nested'));

final map = doc.getMap('settings');
map.setAttr('theme', 'light');
```

## Update Exchange

Use state updates to exchange CRDT state between replicas or providers. Updates
are idempotent and can be safely applied more than once.

```dart
final local = Doc(clientId: ClientId(1));
local.getText('root').insertText(0, 'sync');

final update = encodeStateAsUpdate(local);

final remote = Doc(clientId: ClientId(9));
applyUpdate(remote, update);

print(remote.getText('root').toPlainText()); // sync
```

V2 update helpers are also available:

```dart
final updateV2 = encodeStateAsUpdateV2(local);
applyUpdateV2(remote, updateV2);
```

Providers can also merge updates, diff them against a state vector, and inspect
an update's state vector without first materializing a document:

```dart
final merged = mergeUpdates([update]);
final stateVector = encodeStateVectorFromUpdate(merged);
final missing = diffUpdate(merged, stateVector);
```

## Awareness And Presence

`Awareness` tracks ephemeral presence state such as users, cursors, selections,
and online/offline status. It is provider-neutral: transports can broadcast the
encoded updates over WebSocket, WebRTC, local storage, isolates, or any other
message channel.

```dart
final local = Awareness(localClientId: ClientId(1));
final remote = Awareness(localClientId: ClientId(2));

local.setLocalState({
  'user': {'name': 'Ada'},
  'cursor': 7,
});

final update = encodeAwarenessUpdate(local);
applyAwarenessUpdate(remote, update);
print(remote.states[ClientId(1)]?.toObject());
```

## Rich Text And Deltas

Shared text supports formatting attributes and delta rendering.

```dart
final doc = Doc();
final text = doc.getText('body');

text.insertText(
  0,
  'Important',
  attributes: DeltaAttributes.fromJson({'bold': true}),
);

final delta = text.toDelta();
print(delta.toJson());
```

You can also apply package-native deltas:

```dart
final builder = DeltaBuilder()
  ..insertText(text: 'hello')
  ..retain(
    length: 5,
    attributes: DeltaAttributes.fromJson({'italic': true}),
  );
final delta = builder.done();

text.applyDelta(delta);
```

## Undo And Redo

`UndoManager` tracks CRDT transactions for a document or shared-type scope.

```dart
final doc = Doc(gc: false, clientId: ClientId(9));
final undoManager = UndoManager(doc);
final source = Doc(clientId: ClientId(1));

source.getText('root').insertText(0, 'draft');

applyUpdate(doc, encodeStateAsUpdate(source));

undoManager.undo();
undoManager.redo();
undoManager.destroy();
```

Tracked origins, capture timeouts, delete filters, stack events, and scoped
undo/redo are supported.

## Relative Positions

Relative positions anchor to CRDT content and can be encoded, stored, sent over
the network, and resolved against a document later.

```dart
final source = Doc(clientId: ClientId(1));
source.getText('body').insertText(0, 'hello');

final doc = Doc();
final text = doc.getText('body');
applyUpdate(doc, encodeStateAsUpdate(source));

final position = createRelativePositionFromTypeIndex(text, 2);
final encoded = encodeRelativePosition(position);
final resolved = createAbsolutePositionFromRelativePosition(
  decodeRelativePosition(encoded),
  doc,
);

print(resolved?.index);
```

## Snapshots

Snapshots capture a document version as a state-vector and delete-set pair.
Snapshot restoration requires a source document with garbage collection
disabled so deleted content remains available.

```dart
final doc = Doc(gc: false);
final snap = snapshot(doc);
final bytes = encodeSnapshot(snap);
final restored = createDocFromSnapshot(doc, decodeSnapshot(bytes));
```

## Binary Compatibility

The package includes deterministic V1 and V2 update encoders/decoders, state
vectors, delete sets, update merge/diff helpers, update format conversion,
obfuscation helpers, content-id inspection, serialized fixtures, and compiled
web smoke coverage.

Malformed input is validated with typed exceptions, and binary behavior is
covered by unit, integration, fixture, fuzz, benchmark, and compiled web
checks.

## API Documentation

- Pub package: <https://pub.dev/packages/dart_crdt>
- API docs: <https://pub.dev/documentation/dart_crdt/latest/>
- Repository: <https://github.com/salakar/ycrdt>
- Runnable examples: <https://github.com/salakar/ycrdt/tree/main/packages/dart_crdt/example>

## Stability

`0.2.0` is a pre-1.0 release. Public APIs may change before `1.0.0`,
but binary behavior is covered by regression fixtures and compatibility tests.

## Contributing

See the repository
[CONTRIBUTING.md](https://github.com/salakar/ycrdt/blob/main/CONTRIBUTING.md)
for local setup, formatting, analyzer, tests, coverage, benchmarks, and pull
request expectations.

## Benchmarks

| Field | Value |
| --- | --- |
| Mode | full |
| Generated | 2026-05-08T01:46:16.733514Z |
| Runtime | Dart 3.10.0-247.0.dev, macos, 8 processors |
| Threshold | 500.00 ms/iteration max per benchmark |

| Benchmark | Workload | Iterations | ms/iteration |
| --- | --- | ---: | ---: |
| `update_encoding_round_trip` | Build a text document and encode V1/V2 state updates. | 120 | 1.04 |
| `text_sequential_insert` | Insert single text tokens at monotonically increasing slots. | 120 | 0.52 |
| `text_append` | Append chunked text content to a shared text value. | 120 | 1.18 |
| `text_prepend` | Prepend chunked text content to a shared text value. | 120 | 2.13 |
| `text_middle_insert` | Insert chunked text content into the middle of shared text. | 120 | 1.72 |
| `text_random_insert_delete_format` | Run deterministic random text insert/delete and formatting. | 120 | 2.93 |
| `text_fragmented_delta_render` | Render a large fragmented formatted text value as a delta. | 120 | 9.53 |
| `delta_apply_shallow` | Apply a shallow text delta with retains, inserts, and deletes. | 120 | 2.70 |
| `delta_render_shallow` | Render a shallow delta to stable JSON and debug strings. | 120 | 0.62 |
| `delta_render_deep` | Render nested child and attribute modifications as JSON. | 120 | 0.18 |
| `array_random_insert_delete_nested` | Run deterministic array insert/delete with nested types. | 120 | 63.93 |
| `map_set_delete_conflicts` | Run repeated map set/delete conflicts across clients. | 120 | 0.42 |
| `xml_tree_insert_delete_stringify` | Build, edit, walk, and stringify an XML tree. | 120 | 12.61 |
| `sync_v1_encode_apply_merge_diff` | Encode, apply, merge, and diff V1 state updates. | 120 | 12.04 |
| `sync_v2_encode_apply_merge_diff` | Encode, apply, merge, and diff V2 state updates. | 120 | 12.79 |
| `sync_update_format_convert` | Convert V1 updates to V2 and back to V1. | 120 | 12.59 |
| `sync_pending_out_of_order_recovery` | Recover pending structs and delete sets from out-of-order updates. | 120 | 0.15 |
| `metadata_id_set_algebra` | Run IdSet merge, diff, and intersection workloads. | 120 | 2.23 |
| `metadata_id_map_algebra` | Run IdMap merge, diff, intersection, and filter workloads. | 120 | 74.75 |
| `advanced_relative_position_create_resolve` | Create, encode, decode, and resolve relative positions. | 120 | 1.24 |
| `advanced_snapshot_create_restore_containment` | Create, encode, decode, restore, and check snapshots. | 120 | 1.44 |
| `advanced_undo_redo_stack` | Create undo stack items, undo, redo, and clear stacks. | 120 | 5.34 |
| `advanced_attribution_diff_render_accept_reject_filter` | Diff, render, accept, reject, and filter attributions. | 120 | 0.23 |
| `advanced_gc_enabled_vs_disabled` | Compare GC enabled and disabled delete-heavy workloads. | 120 | 0.74 |

## License

Apache License 2.0. Copyright 2026 Mike Diarmid.
