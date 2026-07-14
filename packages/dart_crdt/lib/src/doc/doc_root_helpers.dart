part of 'doc.dart';

/// Convenience root accessors for common shared type families.
extension DocRootHelpers on Doc {
  /// Returns a root shared map.
  SharedType getMap([String name = _defaultRootName]) {
    return get(name);
  }

  /// Returns a root shared array.
  SharedType getArray([String name = _defaultRootName]) {
    return get(name, SharedTypeKind.array);
  }

  /// Returns a root shared text value.
  SharedType getText([String name = _defaultRootName]) {
    return get(name, SharedTypeKind.text);
  }

  /// Returns a root XML fragment.
  SharedType getXmlFragment([String name = _defaultRootName]) {
    return get(name, SharedTypeKind.xmlFragment);
  }
}
