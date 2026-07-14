import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';

/// Creates a document whose store contains one string item.
Doc docWithStringItem({
  required int client,
  required String parent,
  required String text,
}) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    Item(
      id: Id(client: ClientId(client), clock: Clock(0)),
      parent: doc.itemParentForKey(parent),
      content: ContentString(text),
    ),
  );
  return doc;
}

/// Adds [subdocument] through a transaction and records the subdoc event fields.
void addSubdocumentInTransaction(Doc doc, Subdocument subdocument) {
  doc.transact(
    (transaction) {
      if (doc.addSubdocument(subdocument)) {
        transaction.addSubdocument(subdocument);
      }
      if (subdocument.shouldLoad) {
        transaction.loadSubdocument(subdocument);
      }
    },
    origin: subdocument,
  );
}

/// Removes [subdocument] through a transaction and records the subdoc event.
void removeSubdocumentInTransaction(Doc doc, Subdocument subdocument) {
  doc.transact(
    (transaction) {
      if (doc.removeSubdocument(subdocument)) {
        transaction.removeSubdocument(subdocument);
      }
    },
    origin: subdocument,
  );
}
