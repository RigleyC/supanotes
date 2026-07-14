part of 'doc.dart';

/// Callback invoked inside a document transaction.
typedef TransactionCallback<T> = T Function(Transaction transaction);

/// A document transaction and its collected side effects.
final class Transaction {
  Transaction._({
    required this.doc,
    required this.origin,
    required this.local,
    required Map<ClientId, Clock> beforeState,
  }) : beforeState = Map<ClientId, Clock>.unmodifiable(beforeState);

  final Map<Object, Set<Object?>> _changed =
      LinkedHashMap<Object, Set<Object?>>.identity();
  final Map<Object, List<Object>> _changedParentTypes =
      LinkedHashMap<Object, List<Object>>.identity();
  final Map<Object, Object?> _metadata =
      LinkedHashMap<Object, Object?>.identity();
  final List<AbstractStruct> _mergeStructs = <AbstractStruct>[];
  final Set<Subdocument> _subdocsAdded = LinkedHashSet<Subdocument>.identity();
  final Set<Subdocument> _subdocsRemoved =
      LinkedHashSet<Subdocument>.identity();
  final Set<Subdocument> _subdocsLoaded = LinkedHashSet<Subdocument>.identity();
  final List<void Function(Transaction transaction)> _cleanupCallbacks =
      <void Function(Transaction transaction)>[];
  Map<ClientId, Clock> _afterState = const <ClientId, Clock>{};
  bool _done = false;

  /// Document that owns this transaction.
  final Doc doc;

  /// Application origin associated with the outermost transaction.
  final Object? origin;

  /// Whether the transaction was initiated locally.
  final bool local;

  /// Sync state captured before the transaction callback ran.
  final Map<ClientId, Clock> beforeState;

  /// Id ranges deleted during this transaction.
  final IdSet deleteSet = IdSet();

  /// Values that require cleanup during transaction finalization.
  final Set<Object> cleanupSet = LinkedHashSet<Object>.identity();

  /// Id ranges inserted during this transaction.
  final IdSet insertSet = IdSet();

  /// Whether rich-text formatting cleanup is required.
  bool shouldCleanupFormatting = false;

  /// Whether cleanup has completed.
  bool get done => _done;

  /// Sync state captured during cleanup after the callback completed.
  Map<ClientId, Clock> get afterState => _afterState;

  /// Changed types and changed keys collected during the transaction.
  Map<Object, Set<Object?>> get changed {
    final result = LinkedHashMap<Object, Set<Object?>>.identity();
    for (final entry in _changed.entries) {
      result[entry.key] = Set<Object?>.unmodifiable(entry.value);
    }
    return Map<Object, Set<Object?>>.unmodifiable(result);
  }

  /// Parent type change events collected during the transaction.
  Map<Object, List<Object>> get changedParentTypes {
    final result = LinkedHashMap<Object, List<Object>>.identity();
    for (final entry in _changedParentTypes.entries) {
      result[entry.key] = List<Object>.unmodifiable(entry.value);
    }
    return Map<Object, List<Object>>.unmodifiable(result);
  }

  /// Metadata associated with this transaction.
  Map<Object, Object?> get metadata => Map<Object, Object?>.unmodifiable(
        _metadata,
      );

  /// Structs that should be considered for merge during cleanup.
  List<AbstractStruct> get mergeStructs {
    return List<AbstractStruct>.unmodifiable(_mergeStructs);
  }

  /// Subdocuments added during this transaction.
  Set<Subdocument> get subdocsAdded {
    return Set<Subdocument>.unmodifiable(_subdocsAdded);
  }

  /// Subdocuments removed during this transaction.
  Set<Subdocument> get subdocsRemoved {
    return Set<Subdocument>.unmodifiable(_subdocsRemoved);
  }

  /// Subdocuments loaded during this transaction.
  Set<Subdocument> get subdocsLoaded {
    return Set<Subdocument>.unmodifiable(_subdocsLoaded);
  }

  /// Marks [key] as changed on [type].
  void markChanged(Object type, [Object? key]) {
    (_changed[type] ??= <Object?>{}).add(key);
  }

  /// Records a parent type change [event] for [type].
  void markParentChanged(Object type, Object event) {
    (_changedParentTypes[type] ??= <Object>[]).add(event);
  }

  /// Adds [value] to the transaction cleanup set.
  void addCleanupTarget(Object value) {
    cleanupSet.add(value);
  }

  /// Adds [struct] to the merge queue.
  void queueMerge(AbstractStruct struct) {
    _mergeStructs.add(struct);
  }

  /// Records an inserted [range] for [client].
  void addInsertedRange(ClientId client, IdRange range) {
    insertSet.addRange(client, range);
  }

  /// Records a deleted [range] for [client].
  void addDeletedRange(ClientId client, IdRange range) {
    deleteSet.addRange(client, range);
  }

  /// Stores transaction metadata for [key].
  void setMeta(Object key, Object? value) {
    _metadata[key] = value;
  }

  /// Returns metadata stored for [key].
  Object? getMeta(Object key) => _metadata[key];

  /// Returns whether metadata exists for [key].
  bool hasMeta(Object key) => _metadata.containsKey(key);

  /// Removes metadata stored for [key].
  bool deleteMeta(Object key) {
    final hadKey = _metadata.containsKey(key);
    _metadata.remove(key);
    return hadKey;
  }

  /// Records a subdocument added during the transaction.
  void addSubdocument(Subdocument document) {
    _subdocsAdded.add(document);
  }

  /// Records a subdocument removed during the transaction.
  void removeSubdocument(Subdocument document) {
    _subdocsRemoved.add(document);
  }

  /// Records a subdocument loaded during the transaction.
  void loadSubdocument(Subdocument document) {
    _subdocsLoaded.add(document);
  }

  /// Runs [callback] during transaction cleanup.
  void addCleanupCallback(void Function(Transaction transaction) callback) {
    _cleanupCallbacks.add(callback);
  }

  void _finish(Map<ClientId, Clock> afterState) {
    if (_done) {
      return;
    }

    _afterState = Map<ClientId, Clock>.unmodifiable(afterState);
    Object? error;
    StackTrace? stackTrace;
    void captureError(void Function() callback) {
      try {
        callback();
      } on Object catch (caughtError, caughtStackTrace) {
        error ??= caughtError;
        stackTrace ??= caughtStackTrace;
      }
    }

    try {
      captureError(() => doc._beforeObserverCalls.emit(this));
      _emitSharedTypeEvents(this, captureError);
      captureError(() => doc._afterTransaction.emit(this));
      captureError(() => _cleanupStructs(this));
      for (final callback in _cleanupCallbacks) {
        captureError(() => callback(this));
      }
      _done = true;
      captureError(() => doc._afterTransactionCleanup.emit(this));
      captureError(() => _emitSubdocsEvent(this));
    } finally {
      _done = true;
    }
    if (error != null) {
      Error.throwWithStackTrace(error!, stackTrace!);
    }
  }
}

/// Transaction entrypoints for [Doc].
extension DocTransactions on Doc {
  /// Runs [callback] inside a transaction.
  T transact<T>(
    TransactionCallback<T> callback, {
    Object? origin,
    bool local = true,
  }) {
    final active = _currentTransaction;
    if (active != null) {
      return callback(active);
    }

    final transaction = Transaction._(
      doc: this,
      origin: origin,
      local: local,
      beforeState: store.stateVector(),
    );
    _currentTransaction = transaction;
    _pendingTransactionCleanup.add(transaction);

    Object? error;
    StackTrace? stackTrace;
    T? result;
    try {
      _beforeAllTransactions.emit(this);
      _beforeTransaction.emit(transaction);
      result = callback(transaction);
    } on Object catch (caughtError, caughtStackTrace) {
      error = caughtError;
      stackTrace = caughtStackTrace;
    }

    try {
      _cleanupTransactions();
    } on Object catch (cleanupError, cleanupStackTrace) {
      error ??= cleanupError;
      stackTrace ??= cleanupStackTrace;
    }

    if (error != null) {
      Error.throwWithStackTrace(error, stackTrace!);
    }
    return result as T;
  }

  void _cleanupTransactions() {
    Object? error;
    StackTrace? stackTrace;
    try {
      while (_pendingTransactionCleanup.isNotEmpty) {
        final transaction = _pendingTransactionCleanup.removeAt(0);
        try {
          transaction._finish(store.stateVector());
        } on Object catch (caughtError, caughtStackTrace) {
          error ??= caughtError;
          stackTrace ??= caughtStackTrace;
        }
      }
    } finally {
      _currentTransaction = null;
      try {
        _afterAllTransactions.emit(this);
      } on Object catch (caughtError, caughtStackTrace) {
        error ??= caughtError;
        stackTrace ??= caughtStackTrace;
      }
    }

    if (error != null) {
      Error.throwWithStackTrace(error, stackTrace!);
    }
  }
}
