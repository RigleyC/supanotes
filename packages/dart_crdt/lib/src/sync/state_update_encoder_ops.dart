part of 'state_update.dart';

ByteWriter _restWriter(Object encoder) {
  return switch (encoder) {
    UpdateEncoderV1(:final restWriter) => restWriter,
    UpdateEncoderV2(:final restWriter) => restWriter,
    _ => throw ArgumentError.value(encoder, 'encoder', 'unsupported encoder'),
  };
}

void _writeClient(Object encoder, ClientId client) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeClient(client);
    case UpdateEncoderV2():
      encoder.writeClient(client);
  }
}

void _writeInfo(Object encoder, int info) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeInfo(info);
    case UpdateEncoderV2():
      encoder.writeInfo(info);
  }
}

void _writeLeftId(Object encoder, Id id) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeLeftId(id);
    case UpdateEncoderV2():
      encoder.writeLeftId(id);
  }
}

void _writeRightId(Object encoder, Id id) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeRightId(id);
    case UpdateEncoderV2():
      encoder.writeRightId(id);
  }
}

void _writeParentInfo(Object encoder, bool isKey) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeParentInfo(isKey);
    case UpdateEncoderV2():
      encoder.writeParentInfo(isKey);
  }
}

void _writeString(Object encoder, String value) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeString(value);
    case UpdateEncoderV2():
      encoder.writeString(value);
  }
}

void _writeTypeRef(Object encoder, int typeRef) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeTypeRef(typeRef);
    case UpdateEncoderV2():
      encoder.writeTypeRef(typeRef);
  }
}

void _writeLen(Object encoder, int length) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeLen(length);
    case UpdateEncoderV2():
      encoder.writeLen(length);
  }
}

void _writeAny(Object encoder, AnyValue value) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeAny(value);
    case UpdateEncoderV2():
      encoder.writeAny(value);
  }
}

void _writeBuf(Object encoder, List<int> bytes) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeBuf(bytes);
    case UpdateEncoderV2():
      encoder.writeBuf(bytes);
  }
}

void _writeJson(Object encoder, JsonValue value) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeJson(value);
    case UpdateEncoderV2():
      encoder.writeJson(value);
  }
}

void _writeKey(Object encoder, String key) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeKey(key);
    case UpdateEncoderV2():
      encoder.writeKey(key);
  }
}

void _resetIdSet(Object encoder) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.resetIdSetCurVal();
    case UpdateEncoderV2():
      encoder.resetIdSetCurVal();
  }
}

void _writeIdSetClock(Object encoder, Clock clock) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeIdSetClock(clock);
    case UpdateEncoderV2():
      encoder.writeIdSetClock(clock);
  }
}

void _writeIdSetLen(Object encoder, int length) {
  switch (encoder) {
    case UpdateEncoderV1():
      encoder.writeIdSetLen(length);
    case UpdateEncoderV2():
      encoder.writeIdSetLen(length);
  }
}
