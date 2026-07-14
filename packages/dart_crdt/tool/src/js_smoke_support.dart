part of '../js_smoke.dart';

Doc _docWithItem(int client, String text) {
  final doc = Doc(clientId: ClientId(client));
  doc.store.add(
    Item(
      id: _id(client, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentString(text),
    ),
  );
  return doc;
}

String _rootText(Doc doc) {
  final buffer = StringBuffer();
  for (final item in doc.itemParentForKey('root').items()) {
    if (!item.deleted && item.content is ContentString) {
      buffer.write((item.content as ContentString).value);
    }
  }
  return buffer.toString();
}

int _structCount(Doc doc) {
  var count = 0;
  for (final client in doc.store.clients) {
    count += doc.store.structsFor(client).length;
  }
  return count;
}

String _stateDigest(Map<ClientId, Clock> state) {
  final entries = state.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => '${entry.key.value}:${entry.value.value}')
      .join(',');
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

void _expect(bool condition, String label) {
  if (!condition) {
    throw StateError('Compiled JavaScript smoke failed: $label.');
  }
}
