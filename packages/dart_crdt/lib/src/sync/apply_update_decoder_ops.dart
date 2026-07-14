part of 'apply_update.dart';

ByteReader _restReader(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1(:final restReader) => restReader,
    UpdateDecoderV2(:final restReader) => restReader,
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

ClientId _readClient(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readClient(),
    UpdateDecoderV2() => decoder.readClient(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

int _readInfo(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readInfo(),
    UpdateDecoderV2() => decoder.readInfo(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

Id _readLeftId(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readLeftId(),
    UpdateDecoderV2() => decoder.readLeftId(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

Id _readRightId(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readRightId(),
    UpdateDecoderV2() => decoder.readRightId(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

bool _readParentInfo(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readParentInfo(),
    UpdateDecoderV2() => decoder.readParentInfo(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

String _readString(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readString(),
    UpdateDecoderV2() => decoder.readString(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

int _readTypeRef(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readTypeRef(),
    UpdateDecoderV2() => decoder.readTypeRef(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

int _readLen(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readLen(),
    UpdateDecoderV2() => decoder.readLen(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

AnyValue _readAny(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readAny(),
    UpdateDecoderV2() => decoder.readAny(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

List<int> _readBuf(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readBuf(),
    UpdateDecoderV2() => decoder.readBuf(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

JsonValue _readJson(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readJson(),
    UpdateDecoderV2() => JsonValue.fromObject(decoder.readJson().toObject()),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

String _readKey(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readKey(),
    UpdateDecoderV2() => decoder.readKey(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

void _resetIdSet(Object decoder) {
  switch (decoder) {
    case UpdateDecoderV1():
      decoder.resetIdSetCurVal();
    case UpdateDecoderV2():
      decoder.resetIdSetCurVal();
  }
}

Clock _readIdSetClock(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readIdSetClock(),
    UpdateDecoderV2() => decoder.readIdSetClock(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

int _readIdSetLen(Object decoder) {
  return switch (decoder) {
    UpdateDecoderV1() => decoder.readIdSetLen(),
    UpdateDecoderV2() => decoder.readIdSetLen(),
    _ => throw ArgumentError.value(decoder, 'decoder', 'unsupported decoder'),
  };
}

void _requireRestDone(Object decoder) {
  final reader = _restReader(decoder);
  if (reader.isDone) {
    return;
  }
  throw MalformedUpdateException(
    offset: reader.offset,
    reason: '${reader.remaining} trailing byte(s)',
  );
}
