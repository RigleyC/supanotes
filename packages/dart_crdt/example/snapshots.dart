import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = _docWithRootText('snapshot');
  final snap = snapshot(doc);
  final restored = createDocFromSnapshot(
    doc,
    decodeSnapshot(encodeSnapshot(snap)),
  );

  stdout.writeln('snapshot:text=${_rootText(restored)};empty=${snap.isEmpty}');
}

Doc _docWithRootText(String text) {
  final doc = Doc(gc: false, clientId: ClientId(1));
  doc.getText('root').insertText(0, text);
  return doc;
}

String _rootText(Doc doc) => doc.getText('root').toPlainText();
