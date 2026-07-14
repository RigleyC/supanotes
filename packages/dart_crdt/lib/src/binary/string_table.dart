/// String table encoding for repeated keys and content strings.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'byte_writer.dart';
import 'string_buffer_codec.dart';
import 'varint_codec.dart';

/// Thrown when a string table cannot decode a requested string reference.
final class StringTableExhaustedException implements Exception {
  /// Creates an exception for a read past the declared reference count.
  const StringTableExhaustedException();

  /// A human-readable description of the exhausted table.
  String get message => 'String table has no unread references.';

  @override
  String toString() => 'StringTableExhaustedException: $message';
}

/// Thrown when string table bytes contain an invalid reference.
final class MalformedStringTableException implements FormatException {
  /// Creates an exception for malformed string table input.
  const MalformedStringTableException({
    required this.offset,
    required this.reason,
  });

  @override
  final int offset;

  /// The reason decoding failed.
  final String reason;

  @override
  String get message => 'Malformed string table at offset $offset: $reason.';

  @override
  Object? get source => null;

  @override
  String toString() => 'MalformedStringTableException: $message';
}

/// Encodes repeated strings by assigning stable insertion-order ids.
final class StringTableEncoder {
  /// Creates an empty string table encoder.
  StringTableEncoder() : _referenceWriter = ByteWriter();

  final ByteWriter _referenceWriter;
  final List<String> _strings = <String>[];
  final Map<String, int> _idsByString = <String, int>{};
  int _referenceCount = 0;
  Uint8List? _closedBytes;

  /// The number of unique strings in insertion order.
  int get length => _strings.length;

  /// The number of written string references.
  int get referenceCount => _referenceCount;

  /// Unique strings in stable insertion order.
  List<String> get strings => List<String>.unmodifiable(_strings);

  /// Adds [value] to the table if absent and returns its stable id.
  int intern(String value) {
    _ensureWritable();
    final existing = _idsByString[value];
    if (existing != null) {
      return existing;
    }

    final id = _strings.length;
    _strings.add(value);
    _idsByString[value] = id;
    return id;
  }

  /// Writes a reference to [value] and returns the assigned string id.
  int write(String value) {
    final id = intern(value);
    writeVarUint(_referenceWriter, id);
    _referenceCount += 1;
    return id;
  }

  /// Returns immutable encoded bytes and closes this encoder.
  Uint8List toBytes() {
    if (_closedBytes != null) {
      return _closedBytes!;
    }

    final writer = ByteWriter();
    writeVarUint(writer, _strings.length);
    for (final value in _strings) {
      writeString(writer, value);
    }
    writeVarUint(writer, _referenceCount);
    writer.writeBytes(_referenceWriter.toBytes());
    return _closedBytes ??= writer.toBytes();
  }

  void _ensureWritable() {
    if (_closedBytes != null) {
      throw StateError('Cannot write after encoding has been finalized.');
    }
  }
}

/// Decodes strings from a table and counted reference stream.
final class StringTableDecoder {
  /// Creates a string table decoder over [bytes].
  factory StringTableDecoder(List<int> bytes) {
    return StringTableDecoder._fromReader(ByteReader(bytes));
  }

  StringTableDecoder._({
    required List<String> strings,
    required ByteReader references,
    required int remainingReferences,
  })  : _strings = List<String>.unmodifiable(strings),
        _references = references,
        _remainingReferences = remainingReferences;

  factory StringTableDecoder._fromReader(ByteReader reader) {
    final stringCount = readVarUint(reader);
    final strings = <String>[
      for (var index = 0; index < stringCount; index += 1) readString(reader),
    ];
    final referenceCount = readVarUint(reader);
    return StringTableDecoder._(
      strings: strings,
      references: ByteReader(reader.readBytes(reader.remaining)),
      remainingReferences: referenceCount,
    );
  }

  final List<String> _strings;
  final ByteReader _references;
  int _remainingReferences;

  /// Unique strings in stable insertion order.
  List<String> get strings => _strings;

  /// The number of unread string references.
  int get remainingReferences => _remainingReferences;

  /// Whether every declared string reference has been read.
  bool get isDone => _remainingReferences == 0;

  /// Reads the next string reference.
  String read() {
    if (_remainingReferences == 0) {
      throw const StringTableExhaustedException();
    }

    final idOffset = _references.offset;
    final id = readVarUint(_references);
    _remainingReferences -= 1;
    if (id < _strings.length) {
      return _strings[id];
    }

    throw MalformedStringTableException(
      offset: idOffset,
      reason: 'string id $id is outside table length ${_strings.length}',
    );
  }

  /// Reads exactly [count] string references.
  List<String> readAll(int count) {
    RangeError.checkNotNegative(count, 'count');
    return List<String>.generate(count, (_) => read(), growable: false);
  }
}
