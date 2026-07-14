/// Document lifecycle, options, and root registry state.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import '../binary/any_value.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import '../delta/delta_operation.dart';
import '../events/event_handler.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';

part 'doc_options.dart';
part 'doc_random.dart';
part 'doc_events.dart';
part 'doc_gc.dart';
part 'doc_formatting.dart';
part 'doc_root_helpers.dart';
part 'doc_store_access.dart';
part 'shared_map.dart';
part 'shared_map_store.dart';
part 'shared_sequence.dart';
part 'shared_sequence_store.dart';
part 'shared_text.dart';
part 'shared_text_store_mutation.dart';
part 'shared_text_store_sync.dart';
part 'shared_text_store_target.dart';
part 'shared_type.dart';
part 'shared_xml.dart';
part 'transaction.dart';

/// Root document state for collaborative data structures.
///
/// A document owns root shared types, transactions, event streams, binary
/// update state, and lifecycle flags.
///
/// ```dart
/// final doc = Doc();
/// final body = doc.getText('body');
///
/// doc.transact((transaction) {
///   body.insertText(0, 'Hello');
/// }, origin: 'editor');
/// ```
final class Doc {
  /// Creates a document from named constructor options.
  factory Doc({
    bool gc = true,
    GcFilter? gcFilter,
    String? guid,
    String? collectionId,
    AnyValue? meta,
    bool autoLoad = false,
    bool shouldLoad = false,
    bool isSuggestionDocument = false,
    ClientId? clientId,
  }) {
    return Doc.withOptions(
      DocOptions(
        gc: gc,
        gcFilter: gcFilter,
        guid: guid,
        collectionId: collectionId,
        meta: meta,
        autoLoad: autoLoad,
        shouldLoad: shouldLoad,
        isSuggestionDocument: isSuggestionDocument,
        clientId: clientId,
      ),
    );
  }

  /// Creates a document using [options].
  Doc.withOptions(DocOptions options)
      : gc = options.gc,
        gcFilter = options.gcFilter ?? _allowGarbageCollection,
        guid = options.guid ?? _randomGuid(),
        collectionId = options.collectionId,
        meta = options.meta ?? const JsonNull(),
        autoLoad = options.autoLoad,
        _shouldLoad = options.shouldLoad || options.autoLoad,
        isSuggestionDocument = options.isSuggestionDocument,
        _clientId = options.clientId ?? _randomClientId(),
        store = StructStore();

  final Map<String, SharedType> _share = <String, SharedType>{};
  final Map<String, ItemParent> _itemParentsByKey = <String, ItemParent>{};
  final Map<Id, ItemParent> _itemParentsByItemId = <Id, ItemParent>{};
  final Map<Id, SharedType> _sharedTypeByItemId = <Id, SharedType>{};
  final Set<Subdocument> _subdocs = LinkedHashSet<Subdocument>.identity();
  final Completer<void> _loadedCompleter = Completer<void>();
  final Completer<void> _syncedCompleter = Completer<void>();
  final Completer<void> _destroyedCompleter = Completer<void>();
  final List<Transaction> _pendingTransactionCleanup = <Transaction>[];
  final EventHandler<Doc> _beforeAllTransactions = EventHandler<Doc>();
  final EventHandler<Transaction> _beforeTransaction =
      EventHandler<Transaction>();
  final EventHandler<Transaction> _beforeObserverCalls =
      EventHandler<Transaction>();
  final EventHandler<Transaction> _afterTransaction =
      EventHandler<Transaction>();
  final EventHandler<Transaction> _afterTransactionCleanup =
      EventHandler<Transaction>();
  final EventHandler<Doc> _afterAllTransactions = EventHandler<Doc>();
  final EventHandler<Doc> _onLoad = EventHandler<Doc>();
  final EventHandler<Doc> _onDestroy = EventHandler<Doc>();
  final EventHandler<DocSyncEvent> _onSync = EventHandler<DocSyncEvent>();
  final EventHandler<SubdocsEvent> _onSubdocs = EventHandler<SubdocsEvent>();
  final EventHandler<DocUpdateEvent> _update = EventHandler<DocUpdateEvent>();
  final EventHandler<DocUpdateEvent> _updateV2 = EventHandler<DocUpdateEvent>();

  Transaction? _currentTransaction;
  ClientId _clientId;
  bool _shouldLoad;
  bool _isLoaded = false;
  bool _isSynced = false;
  bool _isDestroyed = false;

  /// Whether deleted content may be garbage-collected.
  final bool gc;

  /// Application-level garbage-collection filter.
  final GcFilter gcFilter;

  /// Stable document id.
  final String guid;

  /// Optional collection id for grouping related documents.
  final String? collectionId;

  /// Application metadata associated with this document.
  final AnyValue meta;

  /// Whether providers should automatically request document loading.
  final bool autoLoad;

  /// Whether this document is used for suggestion or preview state.
  final bool isSuggestionDocument;

  /// Integrated CRDT struct storage for this document.
  final StructStore store;

  /// Currently active transaction, or `null` outside [transact].
  Transaction? get currentTransaction => _currentTransaction;

  /// Whether a transaction is currently active.
  bool get hasActiveTransaction => _currentTransaction != null;

  /// Transactions queued for cleanup.
  List<Transaction> get pendingTransactionCleanup =>
      List<Transaction>.unmodifiable(_pendingTransactionCleanup);

  /// Current local client id.
  ClientId get clientId => _clientId;

  /// Whether this document has been requested for loading.
  bool get shouldLoad => _shouldLoad;

  /// Whether [load] has completed.
  bool get isLoaded => _isLoaded;

  /// Whether a provider has marked this document as synced.
  bool get isSynced => _isSynced;

  /// Whether [destroy] has been called.
  bool get isDestroyed => _isDestroyed;

  /// Completes the first time [load] succeeds.
  Future<void> get whenLoaded => _loadedCompleter.future;

  /// Completes the first time [setSynced] is called with `true`.
  Future<void> get whenSynced => _syncedCompleter.future;

  /// Completes the first time [destroy] is called.
  Future<void> get whenDestroyed => _destroyedCompleter.future;

  /// Emits before the first transaction in a root transaction group.
  EventHandler<Doc> get beforeAllTransactions => _beforeAllTransactions;

  /// Emits before a root transaction callback runs.
  EventHandler<Transaction> get beforeTransaction => _beforeTransaction;

  /// Emits before transaction observers are called.
  EventHandler<Transaction> get beforeObserverCalls => _beforeObserverCalls;

  /// Emits after transaction observers have been called.
  EventHandler<Transaction> get afterTransaction => _afterTransaction;

  /// Emits after transaction cleanup has completed.
  EventHandler<Transaction> get afterTransactionCleanup {
    return _afterTransactionCleanup;
  }

  /// Emits after every pending transaction cleanup has completed.
  EventHandler<Doc> get afterAllTransactions => _afterAllTransactions;

  /// Emits after a V1 update has been applied to this document.
  EventHandler<DocUpdateEvent> get update => _update;

  /// Emits after a V2 update has been applied to this document.
  EventHandler<DocUpdateEvent> get updateV2 => _updateV2;

  /// Snapshot of currently tracked subdocuments.
  Set<Subdocument> get subdocs => Set<Subdocument>.unmodifiable(_subdocs);

  /// Marks this document as requested for loading and loaded.
  Future<void> load() {
    _shouldLoad = true;
    if (!_isLoaded) {
      _isLoaded = true;
      _loadedCompleter.complete();
      _onLoad.emit(this);
    }
    return whenLoaded;
  }

  /// Updates provider sync state.
  void setSynced(bool synced) {
    if (_isSynced == synced) {
      return;
    }

    _isSynced = synced;
    if (synced && !_syncedCompleter.isCompleted) {
      _syncedCompleter.complete();
    }
    _onSync.emit(DocSyncEvent(doc: this, synced: synced));
  }

  /// Marks this document as destroyed.
  Future<void> destroy() {
    if (!_isDestroyed) {
      _isDestroyed = true;
      setSynced(false);
      _destroyedCompleter.complete();
      _onDestroy.emit(this);
    }
    return whenDestroyed;
  }

  /// Replaces the current client id after a detected remote conflict.
  void replaceClientId([ClientId? clientId]) =>
      _clientId = clientId ?? _randomClientId();

  /// Adds [document] to the tracked subdocument set.
  bool addSubdocument(Subdocument document) {
    final added = _subdocs.add(document);
    if (added) {
      _bindSubdocument(this, document);
    }
    return added;
  }

  /// Removes [document] from the tracked subdocument set.
  bool removeSubdocument(Subdocument document) {
    final removed = _subdocs.remove(document);
    if (removed) {
      document.unbindParent();
    }
    return removed;
  }

  /// Returns a defensive snapshot of tracked subdocuments.
  Set<Subdocument> getSubdocs() => subdocs;

  /// Returns the CRDT item parent registered for root [key].
  ItemParent itemParentForKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    return _itemParentsByKey.putIfAbsent(key, () => ItemParent(key: key));
  }

  /// Returns the tracked subdocument guids.
  Set<String> getSubdocGuids() {
    return Set<String>.unmodifiable(
      _subdocs.map((document) => document.guid),
    );
  }
}
