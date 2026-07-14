import 'dart:io';
import 'dart:math';

import 'package:dart_crdt/src/binary/any_value.dart';
import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/delta/delta_operation.dart';
import 'package:dart_crdt/src/relative_position/relative_position.dart';
import 'package:dart_crdt/src/snapshot/snapshot.dart';
import 'package:dart_crdt/src/sync/update_encoder.dart';
import 'package:dart_crdt/src/sync/update_inspection.dart';
import 'package:test/test.dart';

const _testPath = 'test/integration/fuzz/invalid_input_fuzz_test.dart';
const _defaultSeed = 0x5eed66;
const _shortRuns = 64;
const _longRuns = 512;

void main() {
  group('invalid input fuzzing', () {
    _fuzz('binary readers reject invalid access', (random) {
      final bytes = _bytes(random, maxLength: 8);
      final reader = ByteReader(bytes);
      switch (random.nextInt(4)) {
        case 0:
          expect(
            () => ByteReader([...bytes, _invalidByte(random)]),
            throwsRangeError,
          );
        case 1:
          reader.skip(bytes.length);
          expect(reader.isDone, isTrue);
          expect(reader.readByte, throwsA(isA<Exception>()));
        case 2:
          final count = bytes.length + random.nextInt(8) + 1;
          expect(
            () => ByteReader(bytes).readBytes(count),
            throwsA(isA<Exception>()),
          );
        case 3:
          expect(() => reader.skip(-random.nextInt(8) - 1), throwsRangeError);
      }
    });

    _fuzz('update decoders reject trailing invalid input', (random) {
      final trailing = _bytes(random, minLength: 1, maxLength: 8);
      final v1 = <int>[0, 0, ...trailing];
      final v2 = <int>[...UpdateEncoderV2().toBytes(), ...trailing];

      expect(() => decodeUpdate(v1), throwsA(isA<Object>()));
      expect(() => decodeUpdateV2(v2), throwsA(isA<Object>()));
    });

    _fuzz('snapshot decoders reject trailing invalid input', (random) {
      final trailing = _bytes(random, minLength: 1, maxLength: 8);
      final bytes = <int>[0, 0, ...trailing];

      expect(() => decodeSnapshot(bytes), throwsA(isA<Object>()));
      expect(() => decodeSnapshotV2(bytes), throwsA(isA<Object>()));
    });

    _fuzz('relative position decoders reject unknown anchors', (random) {
      final kind = 3 + random.nextInt(120);
      final bytes = <int>[kind, ..._bytes(random, maxLength: 6)];

      expect(() => decodeRelativePosition(bytes), throwsA(isA<Object>()));
    });

    _fuzz('malformed delta values are rejected', (random) {
      final cases = <void Function()>[
        () => DeltaRetain(length: -random.nextInt(32)),
        () => DeltaDelete(-random.nextInt(32)),
        () => DeltaInsertText(text: ''),
        () => DeltaInsertListContent(const <AnyValue>[]),
        () => DeltaAttributes([
              DeltaAttributeSet(key: 'same', value: true),
              DeltaAttributeDelete('same'),
            ]),
        () => DeltaInsertText(
              text: 'x',
              attributes: DeltaAttributes.fromJson({'bad': null}),
            ),
        () => DeltaSetAttribute(key: 'k', value: null),
        () => DeltaDeleteAttribute(''),
        () => DeltaModifyChild(operations: const <DeltaOperation>[]),
        () => DeltaModifyAttribute(
              key: random.nextBool() ? '' : 'child',
              operations: const <DeltaOperation>[],
            ),
      ];

      expect(cases[random.nextInt(cases.length)], throwsA(isA<Object>()));
    });
  });
}

void _fuzz(String name, void Function(Random random) body) {
  test(name, () {
    final config = _FuzzConfig.fromEnvironment();
    printOnFailure('Fuzz seed: ${config.seed}');
    printOnFailure('Fuzz runs: ${config.runs}');
    printOnFailure('Reproduce: ${_reproCommand(config.seed, config.runs)}');

    for (var index = 0; index < config.runs; index += 1) {
      final caseSeed = _caseSeed(config.seed, index);
      try {
        body(Random(caseSeed));
      } on Object catch (error, stackTrace) {
        fail(
          'Fuzz failure at iteration $index with case seed $caseSeed.\n'
          'Reproduce: ${_reproCommand(caseSeed, 1)}\n'
          'Error: $error\n$stackTrace',
        );
      }
    }
  });
}

List<int> _bytes(
  Random random, {
  int minLength = 0,
  required int maxLength,
}) {
  final length = minLength + random.nextInt(maxLength - minLength + 1);
  return [for (var index = 0; index < length; index += 1) random.nextInt(256)];
}

int _invalidByte(Random random) {
  return random.nextBool()
      ? -random.nextInt(1000) - 1
      : 256 + random.nextInt(1000);
}

int _caseSeed(int seed, int index) {
  return (seed ^ (0x9e3779b9 * (index + 1))) & 0x3fffffff;
}

String _reproCommand(int seed, int runs) {
  return 'DART_CRDT_FUZZ_SEED=$seed DART_CRDT_FUZZ_RUNS=$runs '
      'dart test $_testPath';
}

final class _FuzzConfig {
  const _FuzzConfig({required this.seed, required this.runs});

  final int seed;
  final int runs;

  factory _FuzzConfig.fromEnvironment() {
    final env = Platform.environment;
    final seed = int.tryParse(env['DART_CRDT_FUZZ_SEED'] ?? '') ?? _defaultSeed;
    final defaultRuns =
        env['DART_CRDT_LONG_FUZZ'] == '1' ? _longRuns : _shortRuns;
    final runs = int.tryParse(env['DART_CRDT_FUZZ_RUNS'] ?? '') ?? defaultRuns;
    return _FuzzConfig(seed: seed, runs: max(1, runs));
  }
}
