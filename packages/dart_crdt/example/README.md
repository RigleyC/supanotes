# dart_crdt Examples

Run these from the package root with `dart run`:

```sh
dart run example/basic_document.dart
dart run example/update_exchange.dart
dart run example/text_delta.dart
dart run example/undo_redo.dart
dart run example/relative_positions.dart
dart run example/snapshots.dart
```

Each program imports `package:dart_crdt/dart_crdt.dart` and prints deterministic output
so CI can validate that the public examples stay current.
