import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';

/// Creates an item id from integer client and clock parts.
Id advancedId(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

/// Creates a source document with contiguous items under a root parent.
Doc advancedDocWithContent(
  int client,
  List<AbstractContent> contents, {
  String root = 'root',
  bool gc = false,
  bool deleted = false,
}) {
  final doc = Doc(gc: gc, clientId: ClientId(client));
  var clock = 0;
  for (final content in contents) {
    final item = advancedItem(
      doc,
      client,
      clock,
      content,
      root: root,
    );
    if (deleted) {
      item.markDeleted();
    }
    doc.store.add(item);
    clock += content.length;
  }
  return doc;
}

/// Creates a source document with a single root text item.
Doc advancedTextDoc(
  int client,
  String text, {
  String root = 'root',
  bool gc = false,
  bool deleted = false,
}) {
  return advancedDocWithContent(
    client,
    [ContentString(text)],
    root: root,
    gc: gc,
    deleted: deleted,
  );
}

/// Creates an item attached to [doc]'s named root parent.
Item advancedItem(
  Doc doc,
  int client,
  int clock,
  AbstractContent content, {
  String root = 'root',
  String? parentSub,
  Id? origin,
}) {
  return Item(
    id: advancedId(client, clock),
    origin: origin,
    parent: doc.itemParentForKey(root),
    parentSub: parentSub,
    content: content,
  );
}

/// Applies an encoded update from [source] to [target].
void applyAdvancedUpdate(Doc target, Doc source, {Object? origin}) {
  applyUpdate(target, encodeStateAsUpdate(source), origin: origin);
}

/// Creates a clone by applying a V1 update from [source].
Doc cloneAdvancedDoc(Doc source, {bool gc = false}) {
  final target = Doc(gc: gc);
  applyAdvancedUpdate(target, source);
  return target;
}

/// Returns visible root item content in item order.
List<AbstractContent> advancedRootContents(Doc doc, {String root = 'root'}) {
  return [
    for (final item in doc.itemParentForKey(root).items())
      if (!item.deleted) item.content,
  ];
}

/// Returns visible root strings concatenated in item order.
String advancedRootText(Doc doc, {String root = 'root'}) {
  return advancedRootContents(doc, root: root)
      .whereType<ContentString>()
      .map((content) => content.value)
      .join();
}
