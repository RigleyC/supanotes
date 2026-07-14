import 'dart:math';

import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:dart_crdt/src/sync/update_algebra.dart';
import 'package:test/test.dart';

void main() {
  group('concurrent random-position insert re-encode', () {
    test(
      'encodeStateAsUpdate(V2) and mergeUpdates rebuild the converged text '
      'without dropping interleaved concurrent inserts',
      () {
        // Several seeds, so the fix is exercised against many different
        // interleavings rather than one lucky layout.
        for (final seed in <int>[0x5717C4, 0xC0FFEE, 1, 99, 424242]) {
          _runConcurrentReencodeScenario(seed, rounds: 80);
        }
      },
    );
  });
}

/// Drives two clients through [rounds] of genuinely concurrent random-position
/// inserts (each inserts before exchanging) and asserts that every full-state
/// reconstruction path rebuilds the live-converged text exactly: V1
/// `encodeStateAsUpdate`, V2 `encodeStateAsUpdateV2`, and a `mergeUpdates` fold
/// of the exchanged incremental journal.
void _runConcurrentReencodeScenario(int seed, {required int rounds}) {
  final rng = Random(seed);
  const alphabet = 'abcdefghij ';

  final a = Doc(clientId: ClientId(1), gc: false);
  final b = Doc(clientId: ClientId(2), gc: false);
  final textA = a.getText('body');
  final textB = b.getText('body');

  // Every incremental diff exchanged, in arrival order — the journal a relaying
  // worker would post for a later mergeUpdates fold.
  final journal = <List<int>>[];
  var sentA = encodeDocumentStateVector(a);
  var sentB = encodeDocumentStateVector(b);

  for (var round = 0; round < rounds; round += 1) {
    textA.insertText(
      rng.nextInt(textA.length + 1),
      alphabet[rng.nextInt(alphabet.length)],
    );
    textB.insertText(
      rng.nextInt(textB.length + 1),
      alphabet[rng.nextInt(alphabet.length)],
    );

    final diffA = encodeStateAsUpdate(a, sentA);
    final diffB = encodeStateAsUpdate(b, sentB);

    applyUpdate(b, diffA);
    applyUpdate(a, diffB);

    sentA = encodeDocumentStateVector(a);
    sentB = encodeDocumentStateVector(b);
    journal
      ..add(diffA)
      ..add(diffB);
  }

  final live = textA.toPlainText();
  expect(
    textB.toPlainText(),
    live,
    reason: 'clients must converge live (seed $seed)',
  );
  expect(live.length, rounds * 2, reason: 'no inserts lost live (seed $seed)');

  // (1) V1 full-state re-encode of a converged doc, applied to a fresh doc.
  final v1 = Doc(clientId: ClientId(3));
  applyUpdate(v1, encodeStateAsUpdate(a));
  expect(
    v1.getText('body').toPlainText(),
    live,
    reason: 'encodeStateAsUpdate must round-trip the document (seed $seed)',
  );

  // (2) V2 full-state re-encode.
  final v2 = Doc(clientId: ClientId(4));
  applyUpdateV2(v2, encodeStateAsUpdateV2(a));
  expect(
    v2.getText('body').toPlainText(),
    live,
    reason: 'encodeStateAsUpdateV2 must round-trip the document (seed $seed)',
  );

  // (3) mergeUpdates over the concurrent journal, applied to a fresh doc.
  final merged = Doc(clientId: ClientId(5));
  applyUpdate(merged, mergeUpdates(journal));
  expect(
    merged.getText('body').toPlainText(),
    live,
    reason: 'mergeUpdates must fold the concurrent journal (seed $seed)',
  );
}
