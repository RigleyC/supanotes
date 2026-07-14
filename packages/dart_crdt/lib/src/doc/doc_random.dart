part of 'doc.dart';

final _random = Random();

bool _allowGarbageCollection(Object value) => true;

ClientId _randomClientId() {
  const lowBits = 27;
  final high = _random.nextInt(1 << 26);
  final low = _random.nextInt(1 << lowBits);
  return ClientId((high * (1 << lowBits) + low) % (maxSafeInteger + 1));
}

String _randomGuid() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = _randomClientId().value.toRadixString(36);
  return '$timestamp-$random';
}
