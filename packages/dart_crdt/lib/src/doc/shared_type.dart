part of 'doc.dart';

const _defaultRootName = '';

/// Callback invoked for direct shared type changes.
typedef SharedTypeObserver = void Function(SharedTypeEvent event);

/// Callback invoked for shared type changes on a type or its descendants.
typedef SharedTypeDeepObserver = void Function(SharedTypeEvent event);

/// A shared type change event.
final class SharedTypeEvent {
  /// Creates a shared type event.
  SharedTypeEvent({
    required this.target,
    required Set<Object?> keys,
    this.transaction,
  }) : keys = Set<Object?>.unmodifiable(keys);

  /// Shared type that changed.
  final SharedType target;

  /// Changed keys or positions associated with this event.
  final Set<Object?> keys;

  /// Transaction that produced this event, or `null` outside transactions.
  final Transaction? transaction;
}

/// Integrated shared type shell used by document, map, text, and array APIs.
final class SharedType extends SharedTypePlaceholder
    with IterableMixin<Object?> {
  /// Creates a detached shared type.
  SharedType({
    required super.kind,
    super.name,
  }) {
    _validateXmlKindName(kind, name);
  }

  final EventHandler<SharedTypeEvent> _observers =
      EventHandler<SharedTypeEvent>();
  final EventHandler<SharedTypeEvent> _deepObservers =
      EventHandler<SharedTypeEvent>();
  final Map<Object, SharedType> _children = <Object, SharedType>{};
  final Map<String, _AttributeEntry> _attrs = <String, _AttributeEntry>{};
  final Map<String, int> _attrDeleteClocks = <String, int>{};
  final List<Object?> _sequence = <Object?>[];
  final List<SequenceSearchMarker> _searchMarkers = <SequenceSearchMarker>[];
  final List<DeltaAttributes> _textAttributes = <DeltaAttributes>[];
  int _attrClock = 0;

  Doc? _doc;
  SharedType? _parent;
  Object? _parentKey;

  /// Store parent for a nested (non-root) store-backed type, keyed by the id of
  /// its defining `ContentType` item. `null` for roots and detached types.
  ItemParent? _nestedParent;

  /// Document this type is integrated into, or `null` while detached.
  Doc? get doc => _doc;

  /// Parent shared type, or `null` for detached and root types.
  SharedType? get parent => _parent;

  /// Key or index used by [parent] to reference this type.
  Object? get parentKey => _parentKey;

  /// Whether this shared type is integrated into a document.
  bool get isIntegrated => _doc != null;

  /// Whether this shared type is a document root.
  bool get isRoot => _doc != null && _parent == null;

  @override
  int get length {
    _syncSharedTypeView(this);
    return _sequence.length;
  }

  @override
  Iterator<Object?> get iterator {
    _syncSharedTypeView(this);
    return List<Object?>.unmodifiable(_sequence).iterator;
  }

  /// Child shared types keyed by parent-local keys.
  Map<Object, SharedType> get children => Map<Object, SharedType>.unmodifiable(
        _children,
      );

  /// Registers [observer] for direct events.
  EventSubscription observe(SharedTypeObserver observer) {
    return _observers.add(observer);
  }

  /// Removes the first direct observer matching [observer].
  bool unobserve(SharedTypeObserver observer) => _observers.remove(observer);

  /// Registers [observer] for this type and descendant events.
  EventSubscription observeDeep(SharedTypeDeepObserver observer) {
    return _deepObservers.add(observer);
  }

  /// Removes the first deep observer matching [observer].
  bool unobserveDeep(SharedTypeDeepObserver observer) {
    return _deepObservers.remove(observer);
  }

  /// Integrates [child] below this type at [key].
  SharedType integrateChild(Object key, SharedType child) {
    final existing = _children[key];
    if (existing != null && !identical(existing, child)) {
      throw StateError('A child is already integrated for key "$key".');
    }
    child._attachToParent(this, key);
    _children[key] = child;
    return child;
  }

  /// Marks this type as changed.
  void markChanged([Object? key]) {
    final transaction = _doc?.currentTransaction;
    if (transaction != null) {
      transaction.markChanged(this, key);
      return;
    }
    _emitEvent(SharedTypeEvent(target: this, keys: {key}));
  }

  @override
  SharedType copy() {
    _syncSharedTypeView(this);
    final clone = SharedType(kind: kind, name: name);
    _copyAttributesInto(this, clone);
    _copySequenceInto(this, clone);
    _copyTextAttributesInto(this, clone);
    for (final entry in _children.entries) {
      final isAttributeChild =
          entry.key is String && _attrs.containsKey(entry.key);
      if (entry.key is! int && !isAttributeChild) {
        clone.integrateChild(entry.key, entry.value.copy());
      }
    }
    return clone;
  }

  @override
  String toString() => _sharedTypeToString(this);

  void _integrateRoot(Doc doc, String rootName) {
    if (_parent != null) {
      throw StateError('Only detached types can become document roots.');
    }
    _bindDoc(doc);
    if (name != rootName && name.isNotEmpty) {
      throw StateError('Root name "$rootName" conflicts with "$name".');
    }
  }

  void _attachToParent(SharedType parent, Object key) {
    if (identical(parent, this) || parent._hasAncestor(this)) {
      throw StateError('Shared types cannot be integrated into themselves.');
    }
    if (_parent != null && !identical(_parent, parent)) {
      throw StateError('Shared type is already integrated elsewhere.');
    }
    final parentDoc = parent._doc;
    if (_doc != null && parentDoc != null && _doc != parentDoc) {
      throw StateError('Shared type is already integrated into another doc.');
    }
    _parent = parent;
    _parentKey = key;
    if (parentDoc != null) {
      _bindDoc(parentDoc);
    }
  }

  void _detachFromParent(SharedType parent, Object key) {
    if (identical(_parent, parent) && _parentKey == key) {
      _parent = null;
      _parentKey = null;
    }
  }

  void _bindDoc(Doc doc) {
    if (_doc != null && _doc != doc) {
      throw StateError('Shared type is already integrated into another doc.');
    }
    _doc = doc;
    for (final child in _children.values) {
      child._bindDoc(doc);
    }
  }

  /// Binds this type to [doc] and its store [parent] (a nested type's parent).
  void _bindNestedParent(Doc doc, ItemParent parent) {
    _bindDoc(doc);
    _nestedParent = parent;
  }

  bool _hasAncestor(SharedType type) {
    var current = _parent;
    while (current != null) {
      if (identical(current, type)) {
        return true;
      }
      current = current._parent;
    }
    return false;
  }

  void _emitEvent(SharedTypeEvent event) {
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

    captureError(() => _observers.emit(event));
    SharedType? current = this;
    while (current != null) {
      final target = current;
      captureError(() => target._deepObservers.emit(event));
      current = target._parent;
    }
    final dispatchError = error;
    if (dispatchError != null) {
      Error.throwWithStackTrace(dispatchError, stackTrace!);
    }
  }
}

/// Shared type root registry APIs for [Doc].
extension DocSharedTypes on Doc {
  /// Registered root shared types keyed by name.
  Map<String, SharedType> get share => Map<String, SharedType>.unmodifiable(
        _share,
      );

  /// The unnamed default root shared type.
  SharedType get root => get();

  /// Returns the root shared type registered for [name].
  SharedType get([
    String name = _defaultRootName,
    SharedTypeKind kind = SharedTypeKind.map,
  ]) {
    final existing = _share[name];
    if (existing != null) {
      if (existing.kind != kind) {
        throw StateError(
          'Root "$name" is already registered as ${existing.kind.name}.',
        );
      }
      return existing;
    }
    return integrateRoot(SharedType(kind: kind, name: name), name: name);
  }

  /// Integrates [type] as a root shared type named [name].
  SharedType integrateRoot(
    SharedType type, {
    String name = _defaultRootName,
  }) {
    final existing = _share[name];
    if (existing != null && !identical(existing, type)) {
      throw StateError('Root "$name" is already integrated.');
    }
    if (type.kind != (_share[name]?.kind ?? type.kind)) {
      throw StateError('Root "$name" kind mismatch.');
    }
    type._integrateRoot(this, name);
    _share[name] = type;
    return type;
  }

  /// Converts registered roots to stable JSON-compatible debug data.
  Map<String, Object?> toJson() {
    return Map<String, Object?>.unmodifiable({
      for (final entry in _share.entries)
        entry.key: <String, Object?>{
          'kind': entry.value.kind.name,
          'name': entry.value.name,
        },
    });
  }
}
