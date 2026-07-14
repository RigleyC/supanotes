import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final example in _examples) {
    test('example/${example.file} prints deterministic output', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'example/${example.file}'],
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stderr}', isEmpty);
      expect('${result.stdout}'.trim(), example.output);
    });
  }
}

const _examples = <_ExampleCase>[
  _ExampleCase(
    file: 'main.dart',
    output: 'main:text=Hello, local-first Dart.;package=dart_crdt',
  ),
  _ExampleCase(
    file: 'basic_document.dart',
    output:
        'basic:text=Hello, local-first Dart.;items=task-1,task-2;theme=light',
  ),
  _ExampleCase(
    file: 'update_exchange.dart',
    output: 'update:text=sync;clock=4',
  ),
  _ExampleCase(
    file: 'text_delta.dart',
    output: 'text_delta:text=Hello!;ops=2',
  ),
  _ExampleCase(
    file: 'undo_redo.dart',
    output: 'undo_redo:afterUndo=;afterRedo=draft',
  ),
  _ExampleCase(
    file: 'relative_positions.dart',
    output: 'relative:index=2;assoc=0',
  ),
  _ExampleCase(
    file: 'snapshots.dart',
    output: 'snapshot:text=snapshot;empty=false',
  ),
];

final class _ExampleCase {
  const _ExampleCase({
    required this.file,
    required this.output,
  });

  final String file;
  final String output;
}
