part of 'doc.dart';

/// Event emitted when document sync state changes.
final class DocSyncEvent {
  /// Creates a sync event.
  const DocSyncEvent({
    required this.doc,
    required this.synced,
  });

  /// Document whose sync state changed.
  final Doc doc;

  /// Current sync state.
  final bool synced;
}

/// Event emitted after a transaction changes tracked subdocuments.
final class SubdocsEvent {
  /// Creates a subdocument event.
  SubdocsEvent({
    required this.doc,
    required this.transaction,
    required Set<Subdocument> added,
    required Set<Subdocument> removed,
    required Set<Subdocument> loaded,
  })  : added = Set<Subdocument>.unmodifiable(added),
        removed = Set<Subdocument>.unmodifiable(removed),
        loaded = Set<Subdocument>.unmodifiable(loaded);

  /// Parent document.
  final Doc doc;

  /// Transaction that produced the event.
  final Transaction transaction;

  /// Subdocuments added by the transaction.
  final Set<Subdocument> added;

  /// Subdocuments removed by the transaction.
  final Set<Subdocument> removed;

  /// Subdocuments requested for loading by the transaction.
  final Set<Subdocument> loaded;

  /// Whether no subdocument sets changed.
  bool get isEmpty => added.isEmpty && removed.isEmpty && loaded.isEmpty;
}

/// Lifecycle event accessors for [Doc].
extension DocLifecycleEvents on Doc {
  /// Emits when [Doc.load] transitions the document to loaded.
  EventHandler<Doc> get onLoad => _onLoad;

  /// Emits when [Doc.destroy] transitions the document to destroyed.
  EventHandler<Doc> get onDestroy => _onDestroy;

  /// Emits when [Doc.setSynced] changes sync state.
  EventHandler<DocSyncEvent> get onSync => _onSync;

  /// Emits after cleanup when a transaction changes tracked subdocuments.
  EventHandler<SubdocsEvent> get onSubdocs => _onSubdocs;
}

void _bindSubdocument(Doc doc, Subdocument document) {
  document.bindParent(
    SubdocumentParentBinding(
      onLoad: (subdocument) => _recordSubdocumentLoad(doc, subdocument),
      onSync: (_, __) {},
      onDestroy: (subdocument, replacement) {
        _replaceDestroyedSubdocument(doc, subdocument, replacement);
      },
    ),
  );
}

void _recordSubdocumentLoad(Doc doc, Subdocument document) {
  if (!doc._subdocs.contains(document)) {
    return;
  }
  doc.transact(
    (transaction) {
      transaction.loadSubdocument(document);
    },
    origin: document,
  );
}

void _replaceDestroyedSubdocument(
  Doc doc,
  Subdocument document,
  Subdocument replacement,
) {
  doc.transact(
    (transaction) {
      if (doc.removeSubdocument(document)) {
        transaction.removeSubdocument(document);
      }
      if (doc.addSubdocument(replacement)) {
        transaction.addSubdocument(replacement);
        if (replacement.shouldLoad) {
          transaction.loadSubdocument(replacement);
        }
      }
    },
    origin: document,
  );
}

void _emitSubdocsEvent(Transaction transaction) {
  if (transaction.subdocsAdded.isEmpty &&
      transaction.subdocsRemoved.isEmpty &&
      transaction.subdocsLoaded.isEmpty) {
    return;
  }
  transaction.doc._onSubdocs.emit(
    SubdocsEvent(
      doc: transaction.doc,
      transaction: transaction,
      added: transaction.subdocsAdded,
      removed: transaction.subdocsRemoved,
      loaded: transaction.subdocsLoaded,
    ),
  );
}

/// Update event emitted after remote update application.
final class DocUpdateEvent {
  /// Creates an update event with a defensive copy of [update].
  DocUpdateEvent({
    required this.doc,
    required List<int> update,
    required this.origin,
    required this.local,
    required this.version,
  }) : update = Uint8List.fromList(update).asUnmodifiableView();

  /// Document that received the update.
  final Doc doc;

  /// Applied update bytes.
  final Uint8List update;

  /// Origin supplied by the update caller.
  final Object? origin;

  /// Whether the update originated locally.
  final bool local;

  /// Update format version.
  final int version;
}
