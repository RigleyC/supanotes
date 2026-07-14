/// Per-client CRDT struct storage and lookup.
library;

import 'dart:collection';

import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../sync/block_set.dart';
import 'abstract_struct.dart';
import 'id.dart';
import 'pending_update.dart';

part 'struct_store_helpers.dart';
part 'struct_iteration.dart';
part 'struct_compaction.dart';

/// Stores integrated structs keyed by client id and sorted by clock.
final class StructStore implements StructIntegrationTarget, ItemLookup {
  /// Creates an empty struct store.
  StructStore() : _structsByClient = _clientMap();

  /// Creates a store without validating ordering.
  ///
  /// This is intended for integrity-check tests and diagnostics only.
  factory StructStore.debugUnchecked(
    Map<ClientId, Iterable<AbstractStruct>> structsByClient,
  ) {
    final store = StructStore();
    for (final entry in structsByClient.entries) {
      store._structsByClient[entry.key] = List<AbstractStruct>.of(entry.value);
    }
    return store;
  }

  final SplayTreeMap<ClientId, List<AbstractStruct>> _structsByClient;
  BlockSet _pendingStructs = BlockSet();
  IdSet _pendingDeleteSet = IdSet();
  final IdSet _skips = IdSet();
  final IdSet _inserted = IdSet();
  final IdSet _deleted = IdSet();
  final List<PendingStructs> _pendingStructUpdates = <PendingStructs>[];

  /// Clients with stored structs in ascending order.
  List<ClientId> get clients => List<ClientId>.unmodifiable(
        _structsByClient.keys,
      );

  /// Number of clients with stored structs.
  int get clientCount => _structsByClient.length;

  /// Whether no structs are stored.
  bool get isEmpty => _structsByClient.isEmpty;

  /// Whether at least one struct is stored.
  bool get isNotEmpty => _structsByClient.isNotEmpty;

  /// Inserted ranges recorded through [StructIntegrationTarget].
  IdSet get inserted => _copyIdSet(_inserted);

  /// Deleted ranges recorded through [StructIntegrationTarget].
  IdSet get deleted => _copyIdSet(_deleted);

  /// Currently integrated skip ranges.
  IdSet get skips => _copyIdSet(_skips);

  /// Pending struct block ranges waiting for missing dependencies.
  BlockSet get pendingStructs => _copyBlockSet(_pendingStructs);

  /// Pending delete ranges waiting for missing structs.
  IdSet get pendingDeleteSet => _copyIdSet(_pendingDeleteSet);

  /// The most recently recorded pending struct update, or `null` when none are
  /// pending.
  PendingStructs? get pendingStructUpdate =>
      _pendingStructUpdates.isEmpty ? null : _pendingStructUpdates.last;

  /// All causally-incomplete struct updates awaiting missing dependencies.
  List<PendingStructs> get pendingStructUpdates =>
      List<PendingStructs>.unmodifiable(_pendingStructUpdates);

  /// Returns stored structs for [client] in ascending clock order.
  List<AbstractStruct> structsFor(ClientId client) {
    return List<AbstractStruct>.unmodifiable(
      _structsByClient[client] ?? const <AbstractStruct>[],
    );
  }

  /// Returns the exclusive end clock for [client].
  Clock getClock(ClientId client) {
    final structs = _structsByClient[client];
    if (structs == null || structs.isEmpty) {
      return Clock(0);
    }
    return Clock(structs.last.end);
  }

  /// Returns the sync state vector, using first skip clocks as missing state.
  Map<ClientId, Clock> stateVector() {
    final state = _clientMap<Clock>();
    for (final entry in _structsByClient.entries) {
      if (entry.value.isNotEmpty) {
        state[entry.key] = Clock(entry.value.last.end);
      }
    }
    for (final entry in _skips.rangesByClient.entries) {
      if (entry.value.isNotEmpty) {
        state[entry.key] = entry.value.first.start;
      }
    }
    return Map<ClientId, Clock>.unmodifiable(state);
  }

  /// Adds [struct] to the store.
  void add(AbstractStruct struct) => addStruct(struct);

  @override
  void addStruct(AbstractStruct struct) {
    final structs = _structsByClient[struct.id.client];
    if (structs == null) {
      _structsByClient[struct.id.client] = <AbstractStruct>[struct];
      _trackSkip(struct);
      return;
    }
    if (structs.isEmpty || structs.last.end == struct.id.clock.value) {
      structs.add(struct);
      _trackSkip(struct);
      return;
    }
    if (_replaceSkip(structs, struct)) {
      return;
    }
    throw StateError('Structs must append contiguously or replace a skip.');
  }

  /// Returns the struct starting exactly at [id], or `null`.
  AbstractStruct? structAtStart(Id id) {
    final structs = _structsByClient[id.client];
    if (structs == null) {
      return null;
    }
    final index = _lowerBound(structs, id.clock.value);
    if (index < structs.length && structs[index].id.clock == id.clock) {
      return structs[index];
    }
    return null;
  }

  /// Returns the struct containing [id], or `null`.
  AbstractStruct? structContaining(Id id) {
    final structs = _structsByClient[id.client];
    if (structs == null || structs.isEmpty) {
      return null;
    }
    final index = _lowerBound(structs, id.clock.value);
    if (index < structs.length && structs[index].id.clock == id.clock) {
      return structs[index];
    }
    final candidate = index == 0 ? null : structs[index - 1];
    return candidate != null && id.clock.value < candidate.end
        ? candidate
        : null;
  }

  /// Returns the struct containing [id] or throws when missing.
  AbstractStruct getStruct(Id id) {
    final struct = structContaining(id);
    if (struct == null) {
      throw StateError('No struct contains id $id.');
    }
    return struct;
  }

  @override
  Item? itemContaining(Id id) {
    final struct = structContaining(id);
    return struct is Item ? struct : null;
  }

  /// Adds pending struct block ranges.
  void addPendingStructs(BlockSet pending) {
    pending.insertInto(_pendingStructs);
  }

  /// Appends a causally-incomplete struct update awaiting dependencies.
  void addPendingStructUpdate(PendingStructs pending) {
    _pendingStructUpdates.add(pending);
  }

  /// Replaces all pending struct update metadata with [pending] (or clears it
  /// when `null`).
  void setPendingStructUpdate(PendingStructs? pending) {
    _pendingStructUpdates.clear();
    if (pending != null) {
      _pendingStructUpdates.add(pending);
    }
  }

  /// Removes and returns the pending struct updates, also clearing the pending
  /// block ranges so a retry pass can rebuild them from whatever stays pending.
  List<PendingStructs> takePendingStructUpdates() {
    final taken = List<PendingStructs>.of(_pendingStructUpdates);
    _pendingStructUpdates.clear();
    _pendingStructs = BlockSet();
    return taken;
  }

  /// Clears pending struct ranges and raw update metadata.
  void clearPendingStructs() {
    _pendingStructs = BlockSet();
    _pendingStructUpdates.clear();
  }

  /// Adds pending delete ranges.
  void addPendingDeleteSet(IdSet pending) {
    pending.insertInto(_pendingDeleteSet);
  }

  /// Clears pending delete ranges.
  void clearPendingDeleteSet() {
    _pendingDeleteSet = IdSet();
  }

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    _deleted.addRange(client, range);
  }

  @override
  void addInsertedRange(ClientId client, IdRange range) {
    _inserted.addRange(client, range);
  }

  @override
  void addSkippedRange(ClientId client, IdRange range) {
    _skips.addRange(client, range);
  }

  /// Returns diagnostic integrity errors without throwing.
  List<String> debugIntegrityErrors() {
    final errors = <String>[];
    for (final entry in _structsByClient.entries) {
      _checkClientIntegrity(entry.key, entry.value, errors);
    }
    return List<String>.unmodifiable(errors);
  }

  /// Throws when [debugIntegrityErrors] finds any issue.
  void debugAssertIntegrity() {
    final errors = debugIntegrityErrors();
    if (errors.isNotEmpty) {
      throw StateError('StructStore integrity failed: ${errors.join('; ')}');
    }
  }

  bool _replaceSkip(List<AbstractStruct> structs, AbstractStruct struct) {
    final index = _containingIndex(structs, struct.id.clock.value);
    if (index < 0) {
      return false;
    }
    final skip = structs[index];
    if (skip is! Skip ||
        struct.id.clock.value < skip.id.clock.value ||
        struct.end > skip.end) {
      return false;
    }
    final replacements = <AbstractStruct>[
      if (struct.id.clock.value > skip.id.clock.value)
        Skip(
          id: skip.id,
          length: struct.id.clock.value - skip.id.clock.value,
        ),
      struct,
      if (struct.end < skip.end)
        Skip(
          id: struct.id.advance(struct.length),
          length: skip.end - struct.end,
        ),
    ];
    structs.replaceRange(index, index + 1, replacements);
    _skips.deleteRange(struct.id.client, struct.range);
    _trackSkip(struct);
    return true;
  }

  void _trackSkip(AbstractStruct struct) {
    if (struct is Skip) {
      _skips.addRange(struct.id.client, struct.range);
    }
  }
}
