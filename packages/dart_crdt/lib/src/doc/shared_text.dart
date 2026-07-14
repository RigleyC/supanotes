part of 'doc.dart';

const _embedReplacement = '\uFFFC';

/// Text APIs for [SharedType].
///
/// Use these helpers with roots created as [SharedTypeKind.text].
///
/// ```dart
/// final doc = Doc();
/// final body = doc.getText('body');
///
/// body.insertText(0, 'Hello');
/// body.format(0, 5, DeltaAttributes.fromJson({'bold': true}));
///
/// final delta = body.toDelta();
/// assert(delta.operations.length == 1);
/// ```
extension SharedTypeText on SharedType {
  /// Inserts [text] at [index].
  void insertText(
    int index,
    String text, {
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    if (text.isEmpty) {
      return;
    }
    attributes.requireNoDeletes('insertText');
    _insertTextValues(index, _unicodeScalars(text), attributes);
  }

  /// Inserts [embed] at [index].
  void insertEmbed(
    int index,
    Object? embed, {
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    attributes.requireNoDeletes('insertEmbed');
    _insertTextValues(index, <Object?>[embed], attributes);
  }

  /// Deletes [length] text positions from [index].
  void deleteText(int index, int length) {
    _syncRootTextFromStoreIfNeeded(this);
    RangeError.checkNotNegative(length, 'length');
    _ensureTextAttributes();
    if (length == 0) {
      RangeError.checkValueInInterval(index, 0, _sequence.length, 'index');
      return;
    }
    RangeError.checkValueInInterval(
      index,
      0,
      _sequence.length - length,
      'index',
    );
    final document = doc;
    if (document != null && _storeParentFor(this) != null) {
      document.transact((transaction) {
        _deleteRootTextRange(transaction, this, index, length);
        _deleteTextValuesLocal(index, length);
      });
      return;
    }
    _deleteTextValuesLocal(index, length);
  }

  /// Applies [attributes] to [length] text positions from [index].
  void format(int index, int length, DeltaAttributes attributes) {
    _syncRootTextFromStoreIfNeeded(this);
    RangeError.checkNotNegative(length, 'length');
    _ensureTextAttributes();
    if (length == 0 || attributes.isEmpty) {
      RangeError.checkValueInInterval(index, 0, _sequence.length, 'index');
      return;
    }
    RangeError.checkValueInInterval(
      index,
      0,
      _sequence.length - length,
      'index',
    );
    var changed = false;
    for (var offset = 0; offset < length; offset += 1) {
      final attrIndex = index + offset;
      final merged = _mergeAttributes(
        _textAttributes[attrIndex],
        attributes,
      );
      if (merged != _textAttributes[attrIndex]) {
        _textAttributes[attrIndex] = merged;
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    doc?.currentTransaction?.shouldCleanupFormatting = true;
    markChanged(index);
  }

  /// Applies [delta] to this shared text.
  void applyDelta(Delta delta) {
    var index = 0;
    for (final operation in delta.contentOperations) {
      switch (operation) {
        case DeltaInsertText(:final text, :final attributes):
          insertText(index, text, attributes: attributes);
          index += text.runes.length;
        case DeltaInsertListContent(:final values, :final attributes):
          for (final value in values) {
            insertEmbed(index, value.toObject(), attributes: attributes);
            index += 1;
          }
        case DeltaRetain(:final length, :final attributes):
          if (attributes.isNotEmpty) {
            format(index, length, attributes);
          }
          index += length;
        case DeltaDelete(:final length):
          deleteText(index, length);
        case DeltaModifyChild():
          throw UnsupportedError('Child modification is not a text operation.');
        case DeltaSetAttribute() ||
              DeltaDeleteAttribute() ||
              DeltaModifyAttribute():
          throw UnsupportedError('Attribute operation is not text content.');
      }
    }
  }

  /// Renders this shared text as a delta.
  Delta toDelta() {
    _syncRootTextFromStoreIfNeeded(this);
    _ensureTextAttributes();
    final builder = DeltaBuilder();
    var index = 0;
    while (index < _sequence.length) {
      final attributes = _textAttributes[index];
      final value = _sequence[index];
      if (value is String) {
        final buffer = StringBuffer(value);
        index += 1;
        while (index < _sequence.length &&
            _sequence[index] is String &&
            _textAttributes[index] == attributes) {
          buffer.write(_sequence[index]);
          index += 1;
        }
        builder.insertText(text: buffer.toString(), attributes: attributes);
      } else {
        builder.insertObjects(
          <Object?>[_embedToDeltaValue(value)],
          attributes: attributes,
        );
        index += 1;
      }
    }
    return builder.done();
  }

  /// Returns the visible text, using object replacement chars for embeds.
  String toPlainText() {
    _syncRootTextFromStoreIfNeeded(this);
    return _sequence
        .map((value) => value is String ? value : _embedReplacement)
        .join();
  }

  void _insertTextValues(
    int index,
    List<Object?> values,
    DeltaAttributes attributes,
  ) {
    _syncRootTextFromStoreIfNeeded(this);
    RangeError.checkValueInInterval(index, 0, _sequence.length, 'index');
    _ensureTextAttributes();
    for (final value in values) {
      if (value is SharedType) {
        _validateSequenceValue(value);
      }
    }
    final document = doc;
    if (document != null && _storeParentFor(this) != null) {
      document.transact((transaction) {
        _insertTextValuesLocal(index, values, attributes);
        _insertRootTextValues(transaction, this, index, values);
      });
      return;
    }
    _insertTextValuesLocal(index, values, attributes);
  }

  void _insertTextValuesLocal(
    int index,
    List<Object?> values,
    DeltaAttributes attributes,
  ) {
    _sequence.insertAll(index, values);
    _textAttributes.insertAll(
      index,
      List<DeltaAttributes>.filled(values.length, attributes),
    );
    _bindSequenceChildren();
    _setSearchMarker(index);
    markChanged(index);
  }

  void _deleteTextValuesLocal(int index, int length) {
    _sequence.removeRange(index, index + length);
    _textAttributes.removeRange(index, index + length);
    _bindSequenceChildren();
    // _setSearchMarker clamps and guards against an empty sequence itself;
    // pre-clamping here threw `clamp(0, -1)` when the delete emptied the type.
    _setSearchMarker(index);
    markChanged(index);
  }

  void _ensureTextAttributes() {
    while (_textAttributes.length < _sequence.length) {
      _textAttributes.add(DeltaAttributes.empty);
    }
    if (_textAttributes.length > _sequence.length) {
      _textAttributes.removeRange(_sequence.length, _textAttributes.length);
    }
  }
}

List<String> _unicodeScalars(String text) {
  return List<String>.unmodifiable(text.runes.map(String.fromCharCode));
}

DeltaAttributes _mergeAttributes(
  DeltaAttributes current,
  DeltaAttributes changes,
) {
  final merged = <String, Object?>{...current.toJson()};
  for (final change in changes.changes) {
    if (change is DeltaAttributeDelete) {
      merged.remove(change.key);
    } else {
      merged[change.key] = change.toJsonValue();
    }
  }
  return merged.isEmpty
      ? DeltaAttributes.empty
      : DeltaAttributes.fromJson(merged);
}

Object? _embedToDeltaValue(Object? value) {
  if (value is SharedType) {
    return <String, Object?>{
      'kind': value.kind.name,
      'name': value.name,
    };
  }
  return value;
}

void _copyTextAttributesInto(SharedType source, SharedType target) {
  target._textAttributes
    ..clear()
    ..addAll(source._textAttributes);
}

String _sharedTypeToString(SharedType type) {
  return switch (type.kind) {
    SharedTypeKind.text || SharedTypeKind.xmlText => type.toPlainText(),
    SharedTypeKind.xmlElement ||
    SharedTypeKind.xmlFragment =>
      type.toXmlString(),
    _ => '${type.kind.name}:${type.name}',
  };
}
