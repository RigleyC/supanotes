part of 'content.dart';

/// Shared type reference ids used by nested shared-type content.
enum SharedTypeKind {
  /// Array-like shared type.
  array(0),

  /// Map-like shared type.
  map(1),

  /// Text-like shared type.
  text(2),

  /// XML element shared type.
  xmlElement(3),

  /// XML fragment shared type.
  xmlFragment(4),

  /// XML hook shared type.
  xmlHook(5),

  /// XML text shared type.
  xmlText(6);

  const SharedTypeKind(this.ref);

  /// Binary type reference id.
  final int ref;
}

/// Lightweight shared type reference used by nested shared-type content.
base class SharedTypePlaceholder {
  /// Creates a shared type placeholder.
  const SharedTypePlaceholder({
    required this.kind,
    this.name = '',
  });

  /// The shared type kind.
  final SharedTypeKind kind;

  /// Optional debug/root name.
  final String name;

  /// Returns a detached copy.
  SharedTypePlaceholder copy() {
    return SharedTypePlaceholder(kind: kind, name: name);
  }

  /// Writes the placeholder type reference.
  void write(ByteWriter writer) {
    writeVarUint(writer, kind.ref);
    writeString(writer, name);
  }

  @override
  bool operator ==(Object other) {
    return other is SharedTypePlaceholder &&
        kind == other.kind &&
        name == other.name;
  }

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => '${kind.name}:$name';
}

/// Nested shared type content.
final class ContentType extends AbstractContent {
  /// Creates nested shared type content.
  ContentType(this.sharedType);

  /// The nested shared type placeholder.
  SharedTypePlaceholder sharedType;

  @override
  int get ref => contentTypeRef;

  @override
  int get length => 1;

  @override
  bool get isCountable => true;

  @override
  List<Object?> get content => <Object?>[sharedType];

  @override
  ContentType copy() => ContentType(sharedType.copy());

  @override
  ContentType splice(int offset) {
    throw UnsupportedError('Shared type content cannot be split.');
  }

  @override
  bool mergeWith(AbstractContent right) => false;

  @override
  void integrate(ContentLifecycleTarget target) {
    if (target is! NestedContentLifecycleTarget) {
      throw StateError('Nested content lifecycle target required.');
    }
    target.integrateSharedType(sharedType);
  }

  @override
  void delete(ContentLifecycleTarget target) {
    if (target is! NestedContentLifecycleTarget) {
      throw StateError('Nested content lifecycle target required.');
    }
    target.deleteSharedType(sharedType);
  }

  @override
  void gc(ContentLifecycleTarget target) {
    if (target is! NestedContentLifecycleTarget) {
      throw StateError('Nested content lifecycle target required.');
    }
    target.gcSharedType(sharedType);
  }

  @override
  void write(ByteWriter writer, {int offset = 0, int offsetEnd = 0}) {
    encodedLength(offset: offset, offsetEnd: offsetEnd);
    sharedType.write(writer);
  }

  @override
  bool operator ==(Object other) {
    return other is ContentType && sharedType == other.sharedType;
  }

  @override
  int get hashCode => sharedType.hashCode;
}
