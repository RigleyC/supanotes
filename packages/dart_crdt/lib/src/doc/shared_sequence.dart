part of 'doc.dart';

/// Placeholder value for sequence ranges not materialized yet.
final class SequencePlaceholder {
  /// Creates a sequence placeholder.
  const SequencePlaceholder(this.reason);

  /// Diagnostic reason for this placeholder.
  final String reason;

  @override
  bool operator ==(Object other) {
    return other is SequencePlaceholder && reason == other.reason;
  }

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'SequencePlaceholder($reason)';
}

/// Cached index marker used by sequence lookup.
final class SequenceSearchMarker {
  /// Creates a search marker for [index] and [value].
  const SequenceSearchMarker({
    required this.index,
    required this.value,
  });

  /// Visible sequence index.
  final int index;

  /// Value at [index] when the marker was recorded.
  final Object? value;

  @override
  bool operator ==(Object other) {
    return other is SequenceSearchMarker &&
        index == other.index &&
        value == other.value;
  }

  @override
  int get hashCode => Object.hash(index, value);
}

/// Sequence APIs for [SharedType].
extension SharedTypeSequence on SharedType {
  /// Current sequence search markers.
  List<SequenceSearchMarker> get searchMarkers {
    return List<SequenceSearchMarker>.unmodifiable(_searchMarkers);
  }

  /// Inserts [value] at [index].
  void insert(int index, Object? value) {
    insertAll(index, <Object?>[value]);
  }

  /// Inserts [values] at [index].
  void insertAll(int index, Iterable<Object?> values) {
    _syncSharedTypeView(this);
    RangeError.checkValueInInterval(index, 0, _sequence.length, 'index');
    final inserted = List<Object?>.of(values);
    if (inserted.isEmpty) {
      return;
    }
    for (final value in inserted) {
      _validateSequenceValue(value);
    }
    final document = doc;
    if (document != null && _storeParentFor(this) != null) {
      document.transact((transaction) {
        _insertSequenceValuesLocal(index, inserted);
        _insertRootSequenceValues(transaction, this, index, inserted);
      });
      return;
    }
    _insertSequenceValuesLocal(index, inserted);
  }

  /// Appends [value] to the end of the sequence.
  void push(Object? value) {
    _syncSharedTypeView(this);
    insert(_sequence.length, value);
  }

  /// Prepends [value] to the start of the sequence.
  void unshift(Object? value) {
    insert(0, value);
  }

  /// Deletes [length] values starting at [index].
  void delete(int index, [int length = 1]) {
    _syncSharedTypeView(this);
    RangeError.checkNotNegative(length, 'length');
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
        _deleteRootSequenceRange(transaction, this, index, length);
        _deleteSequenceValuesLocal(index, length);
      });
      return;
    }
    _deleteSequenceValuesLocal(index, length);
  }

  /// Returns the value at [index].
  Object? get(int index) {
    _syncSharedTypeView(this);
    RangeError.checkValueInInterval(index, 0, _sequence.length - 1, 'index');
    _setSearchMarker(index);
    return _sequence[index];
  }

  /// Returns a defensive slice from [start] to [end].
  List<Object?> slice([int start = 0, int? end]) {
    _syncSharedTypeView(this);
    final normalizedEnd = end ?? _sequence.length;
    RangeError.checkValueInInterval(start, 0, _sequence.length, 'start');
    RangeError.checkValueInInterval(
      normalizedEnd,
      start,
      _sequence.length,
      'end',
    );
    return List<Object?>.unmodifiable(_sequence.sublist(start, normalizedEnd));
  }

  /// Returns all sequence values as a defensive list.
  List<Object?> toArray() {
    _syncSharedTypeView(this);
    return List<Object?>.unmodifiable(_sequence);
  }

  void _insertSequenceValuesLocal(int index, List<Object?> inserted) {
    _sequence.insertAll(index, inserted);
    _bindSequenceChildren();
    _setSearchMarker(index);
    markChanged(index);
  }

  void _deleteSequenceValuesLocal(int index, int length) {
    _sequence.removeRange(index, index + length);
    _bindSequenceChildren();
    // _setSearchMarker clamps and guards against an empty sequence itself;
    // pre-clamping here threw `clamp(0, -1)` when the delete emptied the type.
    _setSearchMarker(index);
    markChanged(index);
  }

  void _bindSequenceChildren() {
    final oldChildren = <Object, SharedType>{
      for (final entry in _children.entries)
        if (entry.key is int) entry.key: entry.value,
    };
    _children.removeWhere((key, value) => key is int);
    for (var index = 0; index < _sequence.length; index += 1) {
      final value = _sequence[index];
      if (value is SharedType) {
        value._attachToParent(this, index);
        _children[index] = value;
        oldChildren.removeWhere((_, child) => identical(child, value));
      }
    }
    for (final entry in oldChildren.entries) {
      entry.value._detachFromParent(this, entry.key);
    }
  }

  void _setSearchMarker(int index) {
    _searchMarkers.clear();
    if (_sequence.isEmpty || index < 0) {
      return;
    }
    final normalizedIndex = index.clamp(0, _sequence.length - 1);
    _searchMarkers.add(
      SequenceSearchMarker(
        index: normalizedIndex,
        value: _sequence[normalizedIndex],
      ),
    );
  }
}

void _validateSequenceValue(Object? value) {
  if (value is SharedType && value.parent != null) {
    throw StateError('Shared type is already integrated elsewhere.');
  }
}

void _copySequenceInto(SharedType source, SharedType target) {
  for (final value in source._sequence) {
    target.push(value is SharedType ? value.copy() : value);
  }
}
