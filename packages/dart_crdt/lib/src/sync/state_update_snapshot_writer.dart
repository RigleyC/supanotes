part of 'state_update.dart';

/// Writes [document] state up to [stateVector] as a V1 update.
void writeStateAsSnapshotUpdate(
  UpdateEncoderV1 encoder,
  Doc document, {
  required StateVector stateVector,
  required IdSet deleteSet,
}) {
  _writeBoundedStateAsUpdate(
    encoder,
    document.store,
    stateVector,
    deleteSet,
  );
}

/// Writes [document] state up to [stateVector] as a V2 update.
void writeStateAsSnapshotUpdateV2(
  UpdateEncoderV2 encoder,
  Doc document, {
  required StateVector stateVector,
  required IdSet deleteSet,
}) {
  _writeBoundedStateAsUpdate(
    encoder,
    document.store,
    stateVector,
    deleteSet,
  );
}

/// Encodes [document] state up to [stateVector] as a V1 update.
Uint8List encodeStateAsSnapshotUpdate(
  Doc document,
  StateVector stateVector,
  IdSet deleteSet,
) {
  final encoder = UpdateEncoderV1();
  writeStateAsSnapshotUpdate(
    encoder,
    document,
    stateVector: stateVector,
    deleteSet: deleteSet,
  );
  return encoder.toBytes();
}

/// Encodes [document] state up to [stateVector] as a V2 update.
Uint8List encodeStateAsSnapshotUpdateV2(
  Doc document,
  StateVector stateVector,
  IdSet deleteSet,
) {
  final encoder = UpdateEncoderV2();
  writeStateAsSnapshotUpdateV2(
    encoder,
    document,
    stateVector: stateVector,
    deleteSet: deleteSet,
  );
  return encoder.toBytes();
}

void _writeBoundedStateAsUpdate(
  Object encoder,
  StructStore store,
  StateVector stateVector,
  IdSet deleteSet,
) {
  final plans = _boundedClientPlans(store, stateVector);
  writeVarUint(_restWriter(encoder), plans.length);
  for (final plan in plans) {
    _writeClientPlan(encoder, plan);
  }
  _writeDeleteSet(encoder, deleteSet);
}

List<_ClientPlan> _boundedClientPlans(
  StructStore store,
  StateVector stateVector,
) {
  final clients = stateVector.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  final plans = <_ClientPlan>[];
  for (final client in clients) {
    final clock = stateVector[client]!.value;
    if (clock == 0) {
      continue;
    }
    if (store.getClock(client).value < clock) {
      throw StateError('State vector exceeds stored clock for $client.');
    }
    final entries = [
      for (final slice in store.slicesWithoutSplitting(
        client: client,
        range: IdRange(start: Clock(0), length: clock),
      ))
        _StructEntry(
          struct: slice.struct,
          offset: slice.offset,
          offsetEnd: slice.struct.end - slice.range.end,
          start: slice.range.start.value,
          end: slice.range.end,
        ),
    ];
    if (entries.isNotEmpty) {
      plans.add(_ClientPlan(client: client, entries: entries));
    }
  }
  return List<_ClientPlan>.unmodifiable(plans);
}
