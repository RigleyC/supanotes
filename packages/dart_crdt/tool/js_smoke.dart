import 'dart:convert';
import 'dart:math';

import 'package:dart_crdt/src/binary/byte_reader.dart';
import 'package:dart_crdt/src/binary/byte_writer.dart';
import 'package:dart_crdt/src/binary/varint_codec.dart';
import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_set.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:dart_crdt/src/sync/update_algebra.dart';

part 'src/js_smoke_binary.dart';
part 'src/js_smoke_random.dart';
part 'src/js_smoke_support.dart';
part 'src/js_smoke_update.dart';

const _maxSmokeElapsedMs = 30000;

void main() {
  final total = Stopwatch()..start();
  final sections = <String, Object?>{};

  sections['binary'] = _measure(_binaryPrimitiveSmoke);
  sections['updateAlgebra'] = _measure(_updateAlgebraSmoke);
  sections['randomConvergenceV1'] =
      _measure(() => _randomConvergenceSmoke(version: 1));
  sections['randomConvergenceV2'] =
      _measure(() => _randomConvergenceSmoke(version: 2));

  total.stop();
  if (total.elapsedMilliseconds > _maxSmokeElapsedMs) {
    throw StateError(
      'Compiled JavaScript smoke exceeded ${_maxSmokeElapsedMs}ms: '
      '${total.elapsedMilliseconds}ms.',
    );
  }

  // ignore: avoid_print
  print(
    jsonEncode(
      <String, Object?>{
        'status': 'ok',
        'totalElapsedMs': total.elapsedMilliseconds,
        'sections': sections,
      },
    ),
  );
}

Map<String, Object?> _measure(Map<String, Object?> Function() run) {
  final stopwatch = Stopwatch()..start();
  final metrics = run();
  stopwatch.stop();
  return <String, Object?>{
    ...metrics,
    'elapsedMs': stopwatch.elapsedMilliseconds,
  };
}
