part of '../js_smoke.dart';

Map<String, Object?> _updateAlgebraSmoke() {
  final first = encodeStateAsUpdate(_docWithItem(1, 'a'));
  final second = encodeStateAsUpdate(_docWithItem(2, 'b'));
  final target = Doc(clientId: ClientId(9));

  _expect(_sameBytes(mergeUpdates(const []), <int>[0, 0]), 'empty merge');
  applyUpdate(target, first);
  applyUpdate(
    target,
    diffUpdate(mergeUpdates(<List<int>>[first, second, first]), [
      ...encodeDocumentStateVector(target),
    ]),
  );
  _expect(_rootText(target) == 'ab', 'V1 update diff apply');

  final firstV2 = encodeStateAsUpdateV2(_docWithItem(3, 'c'));
  final secondV2 = encodeStateAsUpdateV2(_docWithItem(4, 'd'));
  final targetV2 = Doc(clientId: ClientId(10));
  final mergedV2 = mergeUpdatesV2(<List<int>>[secondV2, firstV2, secondV2]);
  applyUpdateV2(targetV2, diffUpdateV2(mergedV2, encodeStateVector(const {})));
  _expect(_rootText(targetV2) == 'cd', 'V2 update diff apply');

  return <String, Object?>{
    'v1MergedBytes': mergeUpdates(<List<int>>[first, second]).length,
    'v2MergedBytes': mergedV2.length,
    'v1StructCount': _structCount(target),
    'v2StructCount': _structCount(targetV2),
  };
}

bool _sameBytes(List<int> left, List<int> right) {
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
