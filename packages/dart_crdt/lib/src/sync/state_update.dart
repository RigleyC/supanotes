/// Document state encoding as portable update messages.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../binary/any_value.dart';
import '../binary/byte_writer.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import '../doc/doc.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';
import 'state_vector.dart';
import 'update_encoder.dart';

part 'state_update_struct_writer.dart';
part 'state_update_encoder_ops.dart';
part 'state_update_snapshot_writer.dart';

/// Writes [document] state missing from [targetStateVector] to [encoder].
void writeStateAsUpdate(
  UpdateEncoderV1 encoder,
  Doc document, {
  StateVector targetStateVector = const <ClientId, Clock>{},
}) {
  _writeStateAsUpdate(encoder, document.store, targetStateVector);
}

/// Writes [document] state missing from [targetStateVector] to [encoder].
void writeStateAsUpdateV2(
  UpdateEncoderV2 encoder,
  Doc document, {
  StateVector targetStateVector = const <ClientId, Clock>{},
}) {
  _writeStateAsUpdate(encoder, document.store, targetStateVector);
}

/// Encodes [document] state as a V1 update.
///
/// When [encodedTargetStateVector] is provided, only state missing from that
/// vector is written. Passing `null` writes all known state.
Uint8List encodeStateAsUpdate(
  Doc document, [
  List<int>? encodedTargetStateVector,
]) {
  final encoder = UpdateEncoderV1();
  writeStateAsUpdate(
    encoder,
    document,
    targetStateVector: _decodeTargetStateVector(encodedTargetStateVector),
  );
  return encoder.toBytes();
}

/// Encodes [document] state as a V2 update.
///
/// When [encodedTargetStateVector] is provided, only state missing from that
/// vector is written. Passing `null` writes all known state.
Uint8List encodeStateAsUpdateV2(
  Doc document, [
  List<int>? encodedTargetStateVector,
]) {
  final encoder = UpdateEncoderV2();
  writeStateAsUpdateV2(
    encoder,
    document,
    targetStateVector: _decodeTargetStateVector(encodedTargetStateVector),
  );
  return encoder.toBytes();
}

/// Creates a delete set from all deleted structs currently stored in [store].
IdSet createDeleteSetFromStore(StructStore store) {
  final deleteSet = IdSet();
  for (final client in store.clients) {
    for (final struct in store.structsFor(client)) {
      if (struct.deleted) {
        deleteSet.addRange(client, struct.range);
      }
    }
  }
  return deleteSet;
}

void _writeStateAsUpdate(
  Object encoder,
  StructStore store,
  StateVector targetStateVector,
) {
  final plans = _clientPlans(store, targetStateVector);
  writeVarUint(_restWriter(encoder), plans.length);
  for (final plan in plans) {
    _writeClientPlan(encoder, plan);
  }
  _writeDeleteSet(
    encoder,
    createDeleteSetFromStore(store).merged(store.pendingDeleteSet),
  );
}

StateVector _decodeTargetStateVector(List<int>? bytes) {
  if (bytes == null) {
    return const <ClientId, Clock>{};
  }
  return decodeStateVector(bytes);
}

List<_ClientPlan> _clientPlans(
  StructStore store,
  StateVector targetStateVector,
) {
  final storedRanges = <ClientId, List<IdRange>>{};
  final pendingRanges = <ClientId, List<IdRange>>{};

  for (final client in store.clients) {
    final targetClock = targetStateVector[client] ?? Clock(0);
    final storeClock = store.getClock(client);
    if (storeClock.value > targetClock.value) {
      _addRange(
        storedRanges,
        client,
        IdRange(
          start: targetClock,
          length: storeClock.value - targetClock.value,
        ),
      );
    }
  }

  final pending = store.pendingStructs.excludeKnown(targetStateVector);
  for (final client in pending.clients) {
    for (final range in pending.rangesFor(client)) {
      _addRange(pendingRanges, client, range.idRange);
    }
  }

  final clients = <ClientId>{...storedRanges.keys, ...pendingRanges.keys}
      .toList()
    ..sort((left, right) => right.compareTo(left));
  final plans = <_ClientPlan>[];
  for (final client in clients) {
    final entries = <_StructEntry>[
      for (final range in storedRanges[client] ?? const <IdRange>[])
        ..._storedEntries(store, client, range),
      for (final range in pendingRanges[client] ?? const <IdRange>[])
        _pendingEntry(client, range),
    ]..sort((left, right) => left.start.compareTo(right.start));
    final normalized = _normalizeEntries(client, entries);
    if (normalized.isNotEmpty) {
      plans.add(_ClientPlan(client: client, entries: normalized));
    }
  }
  return plans;
}

void _addRange(
  Map<ClientId, List<IdRange>> ranges,
  ClientId client,
  IdRange range,
) {
  if (range.isEmpty) {
    return;
  }
  (ranges[client] ??= <IdRange>[]).add(range);
}

List<_StructEntry> _storedEntries(
  StructStore store,
  ClientId client,
  IdRange range,
) {
  return [
    for (final slice in store.slicesWithoutSplitting(
      client: client,
      range: range,
    ))
      _StructEntry(
        struct: slice.struct,
        offset: slice.offset,
        offsetEnd: slice.struct.end - slice.range.end,
        start: slice.range.start.value,
        end: slice.range.end,
      ),
  ];
}

_StructEntry _pendingEntry(ClientId client, IdRange range) {
  return _StructEntry(
    struct:
        Skip(id: Id(client: client, clock: range.start), length: range.length),
    offset: 0,
    offsetEnd: 0,
    start: range.start.value,
    end: range.end,
  );
}

List<_StructEntry> _normalizeEntries(
  ClientId client,
  List<_StructEntry> entries,
) {
  if (entries.isEmpty) {
    return const <_StructEntry>[];
  }
  var clock = entries.first.start;
  final normalized = <_StructEntry>[];
  for (final entry in entries) {
    if (entry.end <= clock) {
      continue;
    }
    var start = entry.start;
    var offset = entry.offset;
    var struct = entry.struct;
    if (start < clock) {
      final trim = clock - start;
      start = clock;
      if (struct is Skip) {
        struct = Skip(
          id: Id(client: client, clock: Clock(start)),
          length: entry.end - start,
        );
        offset = 0;
      } else {
        offset += trim;
      }
    }
    normalized.add(
      _StructEntry(
        struct: struct,
        offset: offset,
        offsetEnd: entry.offsetEnd,
        start: start,
        end: entry.end,
      ),
    );
    clock = entry.end;
  }
  return List<_StructEntry>.unmodifiable(normalized);
}

final class _ClientPlan {
  const _ClientPlan({
    required this.client,
    required this.entries,
  });

  final ClientId client;
  final List<_StructEntry> entries;
}

final class _StructEntry {
  const _StructEntry({
    required this.struct,
    required this.offset,
    required this.offsetEnd,
    required this.start,
    required this.end,
  });

  final AbstractStruct struct;
  final int offset;
  final int offsetEnd;
  final int start;
  final int end;
}
