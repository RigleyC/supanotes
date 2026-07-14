part of 'content.dart';

/// Parent callbacks used to propagate nested document lifecycle changes.
final class SubdocumentParentBinding {
  /// Creates parent lifecycle callbacks.
  const SubdocumentParentBinding({
    required this.onLoad,
    required this.onSync,
    required this.onDestroy,
  });

  /// Called when the nested document is loaded.
  final void Function(Subdocument document) onLoad;

  /// Called when the nested document sync state changes.
  final void Function(Subdocument document, bool synced) onSync;

  /// Called when the nested document is destroyed and replaced.
  final void Function(Subdocument document, Subdocument replacement) onDestroy;
}

/// Lightweight subdocument placeholder used until full document integration.
final class Subdocument {
  /// Creates a subdocument placeholder.
  Subdocument({
    required this.guid,
    this.collectionId,
    AnyValue? meta,
    this.autoLoad = false,
    bool shouldLoad = false,
  })  : meta = meta ?? const JsonNull(),
        shouldLoad = shouldLoad || autoLoad;

  /// Globally unique document id.
  final String guid;

  /// Optional collection id for grouping subdocuments.
  final String? collectionId;

  /// Application metadata associated with the subdocument.
  final AnyValue meta;

  /// Whether the subdocument should auto-load.
  final bool autoLoad;

  /// Whether the subdocument should be scheduled for load.
  bool shouldLoad;

  Object? _owner;
  SubdocumentParentBinding? _parentBinding;
  final Completer<void> _loadedCompleter = Completer<void>();
  final Completer<void> _syncedCompleter = Completer<void>();
  final Completer<void> _destroyedCompleter = Completer<void>();
  final EventHandler<Subdocument> _load = EventHandler<Subdocument>();
  final EventHandler<Subdocument> _destroy = EventHandler<Subdocument>();
  final EventHandler<bool> _sync = EventHandler<bool>();
  bool _loaded = false;
  bool _synced = false;
  bool _destroyed = false;

  /// Whether this subdocument is currently attached to item content.
  bool get isAttached => _owner != null;

  /// Whether [load] has completed.
  bool get isLoaded => _loaded;

  /// Whether [destroy] has completed.
  bool get isDestroyed => _destroyed;

  /// Whether a provider marked this subdocument as synced.
  bool get isSynced => _synced;

  /// Completes the first time [load] succeeds.
  Future<void> get whenLoaded => _loadedCompleter.future;

  /// Completes the first time [setSynced] is called with `true`.
  Future<void> get whenSynced => _syncedCompleter.future;

  /// Completes the first time [destroy] succeeds.
  Future<void> get whenDestroyed => _destroyedCompleter.future;

  /// Emits when [load] transitions this subdocument to loaded.
  EventHandler<Subdocument> get onLoad => _load;

  /// Emits when [destroy] transitions this subdocument to destroyed.
  EventHandler<Subdocument> get onDestroy => _destroy;

  /// Emits when [setSynced] changes provider sync state.
  EventHandler<bool> get onSync => _sync;

  /// Marks this subdocument as loaded.
  Future<void> load() {
    shouldLoad = true;
    if (!_loaded) {
      _loaded = true;
      _loadedCompleter.complete();
      _load.emit(this);
      _parentBinding?.onLoad(this);
    }
    return whenLoaded;
  }

  /// Updates provider sync state.
  void setSynced(bool synced) {
    if (_synced == synced) {
      return;
    }
    _synced = synced;
    if (synced && !_syncedCompleter.isCompleted) {
      _syncedCompleter.complete();
    }
    _sync.emit(synced);
    _parentBinding?.onSync(this, synced);
  }

  /// Marks this subdocument destroyed and creates an attached replacement.
  Future<void> destroy() {
    if (_destroyed) {
      return whenDestroyed;
    }
    _destroyed = true;
    setSynced(false);
    _destroyedCompleter.complete();
    _destroy.emit(this);
    final replacement = detachedCopy();
    final owner = _owner;
    if (owner is ContentDocument) {
      owner._replaceDestroyedDocument(this, replacement);
    }
    _parentBinding?.onDestroy(this, replacement);
    return whenDestroyed;
  }

  /// Binds provider-neutral parent lifecycle callbacks.
  void bindParent(SubdocumentParentBinding binding) => _parentBinding = binding;

  /// Clears parent lifecycle callbacks.
  void unbindParent() => _parentBinding = null;

  /// Returns a detached copy with the same public metadata.
  Subdocument detachedCopy() {
    return Subdocument(
      guid: guid,
      collectionId: collectionId,
      meta: meta,
      autoLoad: autoLoad,
      shouldLoad: shouldLoad,
    );
  }

  void _attach(Object owner) {
    final currentOwner = _owner;
    if (currentOwner != null && !identical(currentOwner, owner)) {
      throw StateError('Subdocument is already owned by another content item.');
    }
    _owner = owner;
  }

  void _detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is Subdocument &&
        guid == other.guid &&
        collectionId == other.collectionId &&
        meta == other.meta &&
        autoLoad == other.autoLoad &&
        shouldLoad == other.shouldLoad;
  }

  @override
  int get hashCode =>
      Object.hash(guid, collectionId, meta, autoLoad, shouldLoad);

  @override
  String toString() => 'Subdocument($guid)';
}

/// Nested document content.
final class ContentDocument extends AbstractContent {
  /// Creates document content from document metadata.
  ContentDocument({
    required String guid,
    String? collectionId,
    AnyValue? meta,
    bool autoLoad = false,
    bool shouldLoad = false,
  }) : _document = Subdocument(
          guid: guid,
          collectionId: collectionId,
          meta: meta,
          autoLoad: autoLoad,
          shouldLoad: shouldLoad,
        );

  /// Creates document content from an existing [document].
  ContentDocument.fromDocument(Subdocument document) : _document = document;

  Subdocument _document;

  /// The nested document placeholder.
  Subdocument get document => _document;

  @override
  int get ref => contentDocumentRef;

  @override
  int get length => 1;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content => <Object?>[_document];

  @override
  ContentDocument copy() {
    return ContentDocument.fromDocument(_document.detachedCopy());
  }

  @override
  ContentDocument splice(int offset) {
    throw UnsupportedError('Document content cannot be split.');
  }

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(ContentLifecycleTarget target) {
    if (target is! NestedContentLifecycleTarget) {
      throw StateError('Nested content lifecycle target required.');
    }
    _document._attach(this);
    target.addSubdocument(_document);
    if (_document.shouldLoad && !_document.isLoaded) {
      target.loadSubdocument(_document);
    }
  }

  @override
  void delete(ContentLifecycleTarget target) {
    if (target is! NestedContentLifecycleTarget) {
      throw StateError('Nested content lifecycle target required.');
    }
    target.removeSubdocument(_document);
    _document._detach(this);
  }

  void _replaceDestroyedDocument(
    Subdocument current,
    Subdocument replacement,
  ) {
    if (!identical(_document, current)) {
      return;
    }
    current._detach(this);
    _document = replacement;
    replacement._attach(this);
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    writeString(writer, _document.guid);
    writeAnyValue(writer, _documentOptions(_document));
  }

  @override
  bool operator ==(Object other) {
    return other is ContentDocument && _document == other._document;
  }

  @override
  int get hashCode => _document.hashCode;
}

AnyMap _documentOptions(Subdocument document) {
  final entries = <String, AnyValue>{};
  if (document.collectionId != null) {
    entries['collectionId'] = JsonString(document.collectionId!);
  }
  if (document.meta != const JsonNull()) {
    entries['meta'] = document.meta;
  }
  if (document.autoLoad) {
    entries['autoLoad'] = const JsonBool(true);
  }
  if (document.shouldLoad) {
    entries['shouldLoad'] = const JsonBool(true);
  }
  return AnyMap(entries);
}
