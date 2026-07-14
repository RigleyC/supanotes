/// Core CRDT struct contracts and primitive struct variants.
///
/// This library is an advanced compatibility surface. Application code should
/// prefer document, shared-type, update, snapshot, and undo APIs unless it is
/// inspecting or generating low-level binary fixtures.
library;

import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';
import '../content/content.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import 'id.dart';

part 'item.dart';
part 'item_integration.dart';
part 'item_parent.dart';

/// Binary reference number for tombstone structs.
const structGcRefNumber = 0;

/// Binary reference number for skip structs.
const structSkipRefNumber = 10;

/// Receives side effects when a struct is integrated.
abstract interface class StructIntegrationTarget {
  /// Adds [struct] to the backing struct store.
  void addStruct(AbstractStruct struct);

  /// Records that [range] was inserted for [client].
  void addInsertedRange(ClientId client, IdRange range);

  /// Records that [range] was deleted for [client].
  void addDeletedRange(ClientId client, IdRange range);

  /// Records that [range] is missing or skipped for [client].
  void addSkippedRange(ClientId client, IdRange range);
}

/// Base contract for all stored structs.
///
/// This is a low-level storage and binary-encoding contract. Prefer the public
/// document and shared-type APIs unless you are implementing sync, storage, or
/// fixture tooling.
abstract base class AbstractStruct {
  /// Creates a struct at [id] with positive [length].
  AbstractStruct({
    required Id id,
    required int length,
  })  : _id = id,
        _length = _checkLength(id, length);

  Id _id;
  int _length;

  /// The first id covered by this struct.
  Id get id => _id;

  /// The number of client-local clocks covered by this struct.
  int get length => _length;

  /// The exclusive integer end clock.
  int get end => _id.clock.value + _length;

  /// The binary struct reference number.
  int get ref;

  /// Whether this struct represents a content item.
  bool get isItem => false;

  /// Whether this struct is already deleted.
  bool get deleted;

  /// The id range covered by this struct.
  IdRange get range => IdRange(start: _id.clock, length: _length);

  /// Returns whether [other] can be merged directly into this struct.
  bool canMergeWith(AbstractStruct other) {
    return runtimeType == other.runtimeType &&
        _id.client == other._id.client &&
        end == other._id.clock.value;
  }

  /// Attempts to merge [other] into this struct.
  bool mergeWith(AbstractStruct other);

  /// Splits this struct at [diff] clocks and returns the right-side struct.
  AbstractStruct split(int diff);

  /// Integrates this struct into [target], optionally starting at [offset].
  void integrate(StructIntegrationTarget target, {int offset = 0});

  /// Writes this struct with [offset] clocks skipped from the left.
  void write(
    ByteWriter writer, {
    int offset = 0,
    int offsetEnd = 0,
  });

  /// Adds this struct's range to [idSet].
  void addToIdSet(IdSet idSet) {
    idSet.addRange(_id.client, range);
  }

  void _trimStart(int offset) {
    RangeError.checkValueInInterval(offset, 0, _length - 1, 'offset');
    if (offset == 0) {
      return;
    }
    _id = _id.advance(offset);
    _length -= offset;
  }

  void _extendBy(AbstractStruct other) {
    _length = _checkedEndLength(_id, _length + other._length);
  }

  int _encodedLength({
    required int offset,
    required int offsetEnd,
  }) {
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(offsetEnd, 'offsetEnd');
    final encodedLength = _length - offset - offsetEnd;
    if (encodedLength <= 0) {
      throw RangeError.range(encodedLength, 1, _length, 'encodedLength');
    }
    return encodedLength;
  }
}

/// Deleted tombstone replacement struct.
final class GC extends AbstractStruct {
  /// Creates a tombstone struct.
  GC({
    required super.id,
    required super.length,
  });

  @override
  int get ref => structGcRefNumber;

  @override
  bool get deleted => true;

  @override
  bool mergeWith(AbstractStruct other) {
    if (!canMergeWith(other)) {
      return false;
    }
    _extendBy(other);
    return true;
  }

  @override
  GC split(int diff) {
    _checkSplitDiff(diff, length);
    final right = GC(id: id.advance(diff), length: length - diff);
    _length = diff;
    return right;
  }

  @override
  void integrate(StructIntegrationTarget target, {int offset = 0}) {
    _trimStart(offset);
    target
      ..addDeletedRange(id.client, range)
      ..addInsertedRange(id.client, range)
      ..addStruct(this);
  }

  @override
  void write(
    ByteWriter writer, {
    int offset = 0,
    int offsetEnd = 0,
  }) {
    writer.writeByte(ref);
    writeVarUint(
      writer,
      _encodedLength(offset: offset, offsetEnd: offsetEnd),
    );
  }
}

/// Placeholder struct for pending or missing update ranges.
final class Skip extends AbstractStruct {
  /// Creates a skip struct.
  Skip({
    required super.id,
    required super.length,
  });

  @override
  int get ref => structSkipRefNumber;

  @override
  bool get deleted => false;

  @override
  bool mergeWith(AbstractStruct other) {
    if (!canMergeWith(other)) {
      return false;
    }
    _extendBy(other);
    return true;
  }

  @override
  Skip split(int diff) {
    _checkSplitDiff(diff, length);
    final right = Skip(id: id.advance(diff), length: length - diff);
    _length = diff;
    return right;
  }

  @override
  void integrate(StructIntegrationTarget target, {int offset = 0}) {
    _trimStart(offset);
    target
      ..addSkippedRange(id.client, range)
      ..addStruct(this);
  }

  @override
  void write(
    ByteWriter writer, {
    int offset = 0,
    int offsetEnd = 0,
  }) {
    writer.writeByte(ref);
    writeVarUint(
      writer,
      _encodedLength(offset: offset, offsetEnd: offsetEnd),
    );
  }
}

int _checkLength(Id id, int length) {
  RangeError.checkValueInInterval(length, 1, maxSafeInteger, 'length');
  return _checkedEndLength(id, length);
}

int _checkedEndLength(Id id, int length) {
  IdRange(start: id.clock, length: length);
  return length;
}

void _checkSplitDiff(int diff, int length) {
  RangeError.checkValueInInterval(diff, 1, length - 1, 'diff');
}
