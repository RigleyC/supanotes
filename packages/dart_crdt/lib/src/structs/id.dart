/// Lamport-style client and clock identity values.
///
/// These values are public for update metadata, fixture generation, and
/// diagnostics. Most application code should use document and shared-type APIs
/// instead of constructing ids directly.
library;

import '../binary/byte_reader.dart';
import '../binary/byte_writer.dart';
import '../binary/string_buffer_codec.dart';
import '../binary/varint_codec.dart';

/// A globally unique client identifier in the portable 53-bit integer range.
extension type const ClientId._(int _value) implements Object {
  /// Creates a validated client id.
  factory ClientId(int value) {
    RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');
    return ClientId._(value);
  }

  /// The integer representation used by binary encoders.
  int get value => _value;

  /// Compares this client id with [other].
  int compareTo(ClientId other) => _value.compareTo(other._value);

  /// Writes this client id as an unsigned varint.
  void write(ByteWriter writer) {
    writeVarUint(writer, _value);
  }
}

/// A non-negative Lamport clock for a client-local item stream.
extension type const Clock._(int _value) implements Object {
  /// Creates a validated clock.
  factory Clock(int value) {
    RangeError.checkValueInInterval(value, 0, maxSafeInteger, 'value');
    return Clock._(value);
  }

  /// The integer representation used by binary encoders.
  int get value => _value;

  /// Returns a clock advanced by [delta].
  Clock advance(int delta) {
    RangeError.checkNotNegative(delta, 'delta');
    return Clock(_value + delta);
  }

  /// Compares this clock with [other].
  int compareTo(Clock other) => _value.compareTo(other._value);

  /// Writes this clock as an unsigned varint.
  void write(ByteWriter writer) {
    writeVarUint(writer, _value);
  }
}

/// Stable item identifier composed of a client id and a client-local clock.
///
/// This low-level value identifies stored content in binary and metadata APIs.
/// Prefer relative positions for user-facing cursors and selections.
final class Id implements Comparable<Id> {
  /// Creates an item id.
  const Id({
    required this.client,
    required this.clock,
  });

  /// Reads an id from [reader].
  factory Id.read(ByteReader reader) {
    return Id(
      client: readClientId(reader),
      clock: readClock(reader),
    );
  }

  /// The client that created the item.
  final ClientId client;

  /// The client-local item clock.
  final Clock clock;

  /// Returns whether this id belongs to the same client as [other].
  bool hasSameClient(Id other) => client == other.client;

  /// Returns a copy with [clock] advanced by [delta].
  Id advance(int delta) => Id(client: client, clock: clock.advance(delta));

  /// Writes this id as client id followed by clock.
  void write(ByteWriter writer) {
    client.write(writer);
    clock.write(writer);
  }

  /// Converts this id to a stable JSON-compatible map.
  Map<String, int> toJson() => {
        'client': client.value,
        'clock': clock.value,
      };

  @override
  int compareTo(Id other) {
    final clientOrder = client.compareTo(other.client);
    if (clientOrder != 0) {
      return clientOrder;
    }
    return clock.compareTo(other.clock);
  }

  @override
  bool operator ==(Object other) {
    return other is Id && client == other.client && clock == other.clock;
  }

  @override
  int get hashCode => Object.hash(client, clock);

  @override
  String toString() => '${client.value}:${clock.value}';
}

/// Placeholder contract for resolving root-type names to ids.
///
/// Root lookup is implemented later with document and shared-type integration.
abstract interface class RootKeyLookup {
  /// Returns the root key for [id], or `null` when [id] is not a root item.
  String? keyForId(Id id);

  /// Returns the id for [key], or `null` when no root item has that key.
  Id? idForKey(String key);
}

/// Reads a [ClientId] from [reader].
ClientId readClientId(ByteReader reader) => ClientId(readVarUint(reader));

/// Reads a [Clock] from [reader].
Clock readClock(ByteReader reader) => Clock(readVarUint(reader));

/// Writes [clientId] to [writer].
void writeClientId(ByteWriter writer, ClientId clientId) {
  clientId.write(writer);
}

/// Writes [clock] to [writer].
void writeClock(ByteWriter writer, Clock clock) {
  clock.write(writer);
}

/// Encodes a root key placeholder as a length-prefixed string.
void writeRootKey(ByteWriter writer, String key) {
  writeString(writer, key);
}

/// Decodes a root key placeholder from a length-prefixed string.
String readRootKey(ByteReader reader) => readString(reader);
