part of 'doc.dart';

final _xmlNamePattern = RegExp(r'^[A-Za-z_:][A-Za-z0-9_.:-]*$');

/// XML/tree APIs for [SharedType].
extension SharedTypeXml on SharedType {
  /// Appends an XML element child named [name].
  SharedType appendXmlElement(String name) {
    final child = SharedType(kind: SharedTypeKind.xmlElement, name: name);
    push(child);
    return child;
  }

  /// Appends escaped character data as a text node.
  void appendXmlText(String text) {
    insertText(length, text);
  }

  /// Inserts XML [content] after [reference], or at the beginning if `null`.
  void insertXmlAfter(SharedType? reference, Iterable<SharedType> content) {
    final index = reference == null ? 0 : _xmlChildIndex(reference) + 1;
    insertAll(index, content);
  }

  /// Direct XML child elements in sequence order.
  Iterable<SharedType> get xmlChildren {
    return List<SharedType>.unmodifiable(_sequence.whereType<SharedType>());
  }

  /// First XML child element, or `null` when none exists.
  SharedType? get firstChild {
    for (final value in _sequence) {
      if (value is SharedType) {
        return value;
      }
    }
    return null;
  }

  /// Last XML child element, or `null` when none exists.
  SharedType? get lastChild {
    for (var index = _sequence.length - 1; index >= 0; index -= 1) {
      final value = _sequence[index];
      if (value is SharedType) {
        return value;
      }
    }
    return null;
  }

  /// Previous XML sibling, or `null` when none exists.
  SharedType? get previousSibling {
    return _sibling(direction: -1);
  }

  /// Next XML sibling, or `null` when none exists.
  SharedType? get nextSibling {
    return _sibling(direction: 1);
  }

  /// Returns a depth-first snapshot of this type and XML descendants.
  Iterable<SharedType> walkXmlTree({bool includeSelf = true}) {
    final result = <SharedType>[];
    if (includeSelf) {
      result.add(this);
    }
    for (final child in xmlChildren) {
      result.addAll(child.walkXmlTree());
    }
    return List<SharedType>.unmodifiable(result);
  }

  /// Serializes this type as XML.
  String toXmlString() {
    return switch (kind) {
      SharedTypeKind.xmlFragment => _serializeXmlChildren(this),
      SharedTypeKind.xmlElement => _serializeXmlElement(this),
      SharedTypeKind.xmlText => _escapeXmlText(toPlainText()),
      _ => _escapeXmlText(toPlainText()),
    };
  }

  SharedType? _sibling({required int direction}) {
    final parentType = parent;
    if (parentType == null) {
      return null;
    }
    final index =
        parentType._sequence.indexWhere((value) => identical(value, this));
    if (index < 0) {
      return null;
    }
    var cursor = index + direction;
    while (cursor >= 0 && cursor < parentType._sequence.length) {
      final value = parentType._sequence[cursor];
      if (value is SharedType) {
        return value;
      }
      cursor += direction;
    }
    return null;
  }

  int _xmlChildIndex(SharedType reference) {
    final index = _sequence.indexWhere((value) => identical(value, reference));
    if (index < 0) {
      throw StateError('Reference XML child is not contained by this type.');
    }
    return index;
  }
}

void _validateXmlKindName(SharedTypeKind kind, String name) {
  if (kind == SharedTypeKind.xmlElement) {
    _checkXmlName(name, 'name');
  }
}

String _checkXmlName(String value, String name) {
  if (!_xmlNamePattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a valid XML name');
  }
  return value;
}

String _serializeXmlElement(SharedType type) {
  _checkXmlName(type.name, 'name');
  final buffer = StringBuffer()
    ..write('<')
    ..write(type.name);
  for (final entry in type.attrEntries) {
    _checkXmlName(entry.key, 'attribute');
    buffer
      ..write(' ')
      ..write(entry.key)
      ..write('="')
      ..write(_escapeXmlAttribute(entry.value))
      ..write('"');
  }
  if (type._sequence.isEmpty) {
    return (buffer..write('/>')).toString();
  }
  return (buffer
        ..write('>')
        ..write(_serializeXmlChildren(type))
        ..write('</')
        ..write(type.name)
        ..write('>'))
      .toString();
}

String _serializeXmlChildren(SharedType type) {
  final buffer = StringBuffer();
  for (final value in type._sequence) {
    switch (value) {
      case SharedType():
        buffer.write(value.toXmlString());
      case String():
        buffer.write(_escapeXmlText(value));
      case null:
        break;
      default:
        buffer.write(_escapeXmlText(value.toString()));
    }
  }
  return buffer.toString();
}

String _escapeXmlText(Object? value) {
  return value
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _escapeXmlAttribute(Object? value) {
  return _escapeXmlText(value)
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
