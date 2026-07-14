/// Primitive item content variants and binary payload writers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../binary/any_codec.dart';
import '../binary/any_value.dart';
import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';
import '../events/event_handler.dart';

part 'content_codec.dart';
part 'content_collections.dart';
part 'content_nested.dart';
part 'content_scalars.dart';
part 'content_type.dart';

/// Content reference number for deleted ranges.
const contentDeletedRef = 1;

/// Content reference number for JSON array content.
const contentJsonRef = 2;

/// Content reference number for binary content.
const contentBinaryRef = 3;

/// Content reference number for string content.
const contentStringRef = 4;

/// Content reference number for embedded JSON content.
const contentEmbedRef = 5;

/// Content reference number for formatting attributes.
const contentFormatRef = 6;

/// Content reference number for nested shared type content.
const contentTypeRef = 7;

/// Content reference number for arbitrary value arrays.
const contentAnyRef = 8;

/// Content reference number for nested document content.
const contentDocumentRef = 9;

/// Receives content lifecycle side effects during item operations.
abstract interface class ContentLifecycleTarget {
  /// Marks [length] clocks as deleted.
  void markDeleted(int length);

  /// Clears cached formatting/search metadata.
  void clearFormattingCache();

  /// Records that formatting content is present.
  void markHasFormatting();
}

/// Receives nested document and shared-type lifecycle side effects.
abstract interface class NestedContentLifecycleTarget
    implements ContentLifecycleTarget {
  /// Records that [document] was added by a transaction.
  void addSubdocument(Subdocument document);

  /// Records that [document] should be loaded.
  void loadSubdocument(Subdocument document);

  /// Records that [document] was removed by a transaction.
  void removeSubdocument(Subdocument document);

  /// Records integration of [sharedType].
  void integrateSharedType(SharedTypePlaceholder sharedType);

  /// Records deletion of [sharedType].
  void deleteSharedType(SharedTypePlaceholder sharedType);

  /// Records garbage collection of [sharedType].
  void gcSharedType(SharedTypePlaceholder sharedType);
}

/// Base class for all primitive item content variants.
sealed class AbstractContent {
  /// Creates a content value.
  const AbstractContent();

  /// Binary content reference number.
  int get ref;

  /// Number of client-local clocks covered by this content.
  int get length;

  /// Whether this content contributes to visible sequence length.
  bool get isCountable;

  /// Extracts user-visible values represented by this content.
  List<Object?> get content;

  /// Returns a copy of this content.
  AbstractContent copy();

  /// Splits this content at [offset], mutating this value to the left side.
  AbstractContent splice(int offset);

  /// Attempts to merge [right] into this content.
  bool mergeWith(AbstractContent right);

  /// Applies integration side effects.
  void integrate(ContentLifecycleTarget target) {}

  /// Applies deletion side effects.
  void delete(ContentLifecycleTarget target) {}

  /// Applies garbage-collection side effects.
  void gc(ContentLifecycleTarget target) {}

  /// Writes the payload for this content.
  void write(
    ByteWriter writer, {
    int offset = 0,
    int offsetEnd = 0,
  });

  /// Writes [ref] followed by this content payload.
  void writeWithRef(
    ByteWriter writer, {
    int offset = 0,
    int offsetEnd = 0,
  }) {
    writer.writeByte(ref);
    write(writer, offset: offset, offsetEnd: offsetEnd);
  }

  /// Validates a splice offset and returns it.
  int checkSplitOffset(int offset) {
    return RangeError.checkValueInInterval(offset, 1, length - 1, 'offset');
  }

  /// Returns the encoded payload length after trimming.
  int encodedLength({
    required int offset,
    required int offsetEnd,
  }) {
    RangeError.checkNotNegative(offset, 'offset');
    RangeError.checkNotNegative(offsetEnd, 'offsetEnd');
    final result = length - offset - offsetEnd;
    if (result < 0) {
      throw RangeError.range(result, 0, length, 'encodedLength');
    }
    return result;
  }
}

List<T> _immutableCopy<T>(Iterable<T> values) {
  return List<T>.unmodifiable(values);
}

Uint8List _copyBytes(List<int> bytes) {
  final copy = Uint8List(bytes.length);
  for (var index = 0; index < bytes.length; index += 1) {
    final byte = bytes[index];
    RangeError.checkValueInInterval(byte, 0, 255, 'bytes[$index]');
    copy[index] = byte;
  }
  return copy.asUnmodifiableView();
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

int _listHash<T>(Iterable<T> values) => Object.hashAll(values);
