/// Update reading and application APIs.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../binary/any_value.dart';
import '../binary/byte_reader.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import '../doc/doc.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../structs/pending_update.dart';
import '../structs/struct_store.dart';
import 'block_set.dart';
import 'update_decoder.dart';

part 'apply_update_target.dart';
part 'apply_update_struct_reader.dart';
part 'apply_update_decoder_ops.dart';

/// Applies a V1 [update] to [document].
void applyUpdate(
  Doc document,
  List<int> update, {
  Object? origin,
}) {
  _applyUpdateBytes(
    document,
    update,
    origin: origin,
    version: 1,
  );
}

/// Applies a V2 [update] to [document].
void applyUpdateV2(
  Doc document,
  List<int> update, {
  Object? origin,
}) {
  _applyUpdateBytes(
    document,
    update,
    origin: origin,
    version: 2,
  );
}

/// Reads and applies a V1 update from [decoder].
void readUpdate(
  UpdateDecoderV1 decoder,
  Doc document, {
  Object? origin,
  List<int>? update,
}) {
  document.transact(
    (transaction) {
      _readDecodedUpdate(
        decoder,
        transaction,
        updateBytes: update ?? decoder.restReader.toBytes(),
        version: 1,
      );
    },
    origin: origin,
    local: false,
  );
}

/// Reads and applies a V2 update from [decoder].
void readUpdateV2(
  UpdateDecoderV2 decoder,
  Doc document, {
  Object? origin,
  List<int>? update,
}) {
  document.transact(
    (transaction) {
      _readDecodedUpdate(
        decoder,
        transaction,
        updateBytes: update ?? decoder.restReader.toBytes(),
        version: 2,
      );
    },
    origin: origin,
    local: false,
  );
}

void _applyUpdateBytes(
  Doc document,
  List<int> update, {
  required Object? origin,
  required int version,
}) {
  var applied = false;
  document.transact(
    (transaction) {
      applied = _readDecodedUpdate(
        _decoderFor(update, version),
        transaction,
        updateBytes: update,
        version: version,
      );
      if (applied) {
        _retryPendingStructs(transaction);
        _retryPendingDeleteSet(transaction);
      }
    },
    origin: origin,
    local: false,
  );

  if (applied) {
    final event = DocUpdateEvent(
      doc: document,
      update: update,
      origin: origin,
      local: false,
      version: version,
    );
    if (version == 1) {
      document.update.emit(event);
    } else {
      document.updateV2.emit(event);
    }
  }
}

Object _decoderFor(List<int> update, int version) {
  return switch (version) {
    1 => UpdateDecoderV1(update),
    2 => UpdateDecoderV2(update),
    _ => throw ArgumentError.value(version, 'version', 'must be 1 or 2'),
  };
}

bool _readDecodedUpdate(
  Object decoder,
  Transaction transaction, {
  required List<int> updateBytes,
  required int version,
}) {
  final target = _UpdateIntegrationTarget(transaction);
  final blocks = BlockSet();
  final missing = <ClientId, Clock>{};
  var applied = false;

  final clientCount = readVarUint(_restReader(decoder));
  for (var clientIndex = 0; clientIndex < clientCount; clientIndex += 1) {
    final structCount = readVarUint(_restReader(decoder));
    final client = _readClient(decoder);
    var clock = Clock(readVarUint(_restReader(decoder)));
    for (var index = 0; index < structCount; index += 1) {
      final struct = _readStruct(
        decoder,
        transaction.doc,
        Id(client: client, clock: clock),
      );
      blocks.add(struct.id, length: struct.length);
      final didApply = _integrateStruct(struct, target, missing);
      applied = applied || didApply;
      clock = Clock(struct.end);
    }
  }

  final deleteSet = _readDeleteSet(decoder);
  applied = _applyDeleteSet(target, deleteSet, missing) || applied;
  _requireRestDone(decoder);

  if (missing.isNotEmpty) {
    // Append rather than overwrite: a second causally-incomplete update must
    // not discard an earlier one's struct bytes, or those structs are lost
    // forever once their dependencies arrive. Out-of-order delivery is normal
    // on real networks, so multiple updates can be pending simultaneously.
    transaction.doc.store
      ..addPendingStructs(blocks)
      ..addPendingStructUpdate(
        PendingStructs(
          missing: missing,
          update: updateBytes,
          version: version,
        ),
      );
  }
  return applied;
}

bool _integrateStruct(
  AbstractStruct struct,
  _UpdateIntegrationTarget target,
  Map<ClientId, Clock> missing,
) {
  final store = target.store;
  final localClock = store.getClock(struct.id.client);
  if (struct.id.clock.value > localClock.value) {
    missing[struct.id.client] = localClock;
    return false;
  }
  final offset = localClock.value - struct.id.clock.value;
  if (offset >= struct.length) {
    return false;
  }
  if (struct is Item && !_prepareItem(struct, store, missing)) {
    return false;
  }
  struct.integrate(target, offset: offset);
  return true;
}

bool _prepareItem(
  Item item,
  StructStore store,
  Map<ClientId, Clock> missing,
) {
  var hasMissingDependency = false;
  for (final id in [item.origin, item.rightOrigin]) {
    if (id != null && store.itemContaining(id) == null) {
      missing[id.client] = store.getClock(id.client);
      hasMissingDependency = true;
    }
  }
  if (hasMissingDependency) {
    return false;
  }

  _cleanItemBoundaries(item, store);
  if (item.parent != null) {
    return true;
  }
  final parent = _linkedParent(item, store);
  if (parent != null) {
    item.parent = parent;
    return true;
  }
  return false;
}

void _cleanItemBoundaries(Item item, StructStore store) {
  final origin = item.origin;
  if (origin != null) {
    store.cleanEnd(origin);
    item.left = store.itemContaining(origin);
  }
  final rightOrigin = item.rightOrigin;
  if (rightOrigin != null) {
    store.cleanStart(rightOrigin);
    item.right = store.itemContaining(rightOrigin);
  }
}

ItemParent? _linkedParent(Item item, StructStore store) {
  final origin = item.origin;
  if (origin != null) {
    return store.itemContaining(origin)?.parent;
  }
  final rightOrigin = item.rightOrigin;
  if (rightOrigin != null) {
    return store.itemContaining(rightOrigin)?.parent;
  }
  return null;
}
