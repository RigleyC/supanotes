part of 'struct_store.dart';

/// Compaction helpers for [StructStore].
extension StructStoreCompaction on StructStore {
  /// Attempts to merge [struct] with adjacent compatible structs.
  void compactAround(AbstractStruct struct) {
    final structs = _structsByClient[struct.id.client];
    if (structs == null || structs.length < 2) {
      return;
    }
    var index = _identityIndex(structs, struct);
    if (index < 0) {
      index = _lowerBound(structs, struct.id.clock.value);
      if (index >= structs.length ||
          structs[index].id.clock != struct.id.clock) {
        return;
      }
    }
    index = _mergeLeft(structs, index);
    _mergeRight(structs, index);
  }
}

int _identityIndex(List<AbstractStruct> structs, AbstractStruct struct) {
  for (var index = 0; index < structs.length; index += 1) {
    if (identical(structs[index], struct)) {
      return index;
    }
  }
  return -1;
}

int _mergeLeft(List<AbstractStruct> structs, int index) {
  while (index > 0 && structs[index - 1].mergeWith(structs[index])) {
    structs.removeAt(index);
    index -= 1;
  }
  return index;
}

void _mergeRight(List<AbstractStruct> structs, int index) {
  while (index + 1 < structs.length &&
      structs[index].mergeWith(structs[index + 1])) {
    structs.removeAt(index + 1);
  }
}
