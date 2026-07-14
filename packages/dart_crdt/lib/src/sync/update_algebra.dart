/// Update merge and diff helpers.
library;

import 'dart:typed_data';

import '../doc/doc.dart';
import '../structs/id.dart';
import 'apply_update.dart';
import 'state_update.dart';
import 'state_vector.dart';
import 'update_inspection.dart';

/// Merges V1 [updates] into one normalized V1 update.
Uint8List mergeUpdates(Iterable<List<int>> updates) {
  final doc = Doc();
  for (final update in updates) {
    applyUpdate(doc, update);
  }
  _dropUnresolvedPending(doc);
  return encodeStateAsUpdate(doc);
}

/// Merges V2 [updates] into one normalized V2 update.
Uint8List mergeUpdatesV2(Iterable<List<int>> updates) {
  final doc = Doc();
  for (final update in updates) {
    applyUpdateV2(doc, update);
  }
  _dropUnresolvedPending(doc);
  return encodeStateAsUpdateV2(doc);
}

/// Returns the V1 part of [update] missing from [encodedStateVector].
Uint8List diffUpdate(List<int> update, List<int> encodedStateVector) {
  final doc = Doc();
  applyUpdate(doc, update);
  _dropUnresolvedPending(doc);
  return encodeStateAsUpdate(doc, encodedStateVector);
}

/// Returns the V2 part of [update] missing from [encodedStateVector].
Uint8List diffUpdateV2(List<int> update, List<int> encodedStateVector) {
  final doc = Doc();
  applyUpdateV2(doc, update);
  _dropUnresolvedPending(doc);
  return encodeStateAsUpdateV2(doc, encodedStateVector);
}

/// Encodes the state vector represented by a V1 [update].
Uint8List encodeStateVectorFromUpdate(List<int> update) {
  return encodeStateVector(_stateVectorFromUpdate(decodeUpdate(update)));
}

/// Encodes the state vector represented by a V2 [update].
Uint8List encodeStateVectorFromUpdateV2(List<int> update) {
  return encodeStateVectorV2(_stateVectorFromUpdate(decodeUpdateV2(update)));
}

void _dropUnresolvedPending(Doc doc) {
  doc.store
    ..clearPendingStructs()
    ..clearPendingDeleteSet();
}

StateVector _stateVectorFromUpdate(DecodedUpdate update) {
  final state = <ClientId, Clock>{};
  for (final struct in update.structs) {
    final end = Clock(struct.id.clock.value + struct.length);
    final previous = state[struct.id.client];
    if (previous == null || end.value > previous.value) {
      state[struct.id.client] = end;
    }
  }
  return Map<ClientId, Clock>.unmodifiable(state);
}
