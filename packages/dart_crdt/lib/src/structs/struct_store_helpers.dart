part of 'struct_store.dart';

IdSet _copyIdSet(IdSet source) {
  final copy = IdSet();
  source.insertInto(copy);
  return copy;
}

BlockSet _copyBlockSet(BlockSet source) {
  final copy = BlockSet();
  source.insertInto(copy);
  return copy;
}

SplayTreeMap<ClientId, T> _clientMap<T>() {
  return SplayTreeMap<ClientId, T>((left, right) => left.compareTo(right));
}

int _lowerBound(List<AbstractStruct> structs, int clock) {
  var low = 0;
  var high = structs.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (structs[middle].id.clock.value < clock) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

int _containingIndex(List<AbstractStruct> structs, int clock) {
  final index = _lowerBound(structs, clock);
  if (index < structs.length && structs[index].id.clock.value == clock) {
    return index;
  }
  final candidateIndex = index - 1;
  if (candidateIndex >= 0 && clock < structs[candidateIndex].end) {
    return candidateIndex;
  }
  return -1;
}

void _checkClientIntegrity(
  ClientId client,
  List<AbstractStruct> structs,
  List<String> errors,
) {
  var previousEnd = structs.isEmpty ? 0 : structs.first.end;
  for (var index = 0; index < structs.length; index += 1) {
    final struct = structs[index];
    if (struct.id.client != client) {
      errors.add(
        'client ${client.value} contains struct for ${struct.id.client.value}',
      );
    }
    if (index == 0) {
      continue;
    }
    final start = struct.id.clock.value;
    if (start < previousEnd) {
      errors.add('client ${client.value} overlaps at clock $start');
    } else if (start > previousEnd) {
      errors.add('client ${client.value} has gap before clock $start');
    }
    previousEnd = struct.end;
  }
}
