import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final source = _docWithTextRoot('hello');
  final doc = Doc();
  final text = doc.getText('body');

  applyUpdate(doc, encodeStateAsUpdate(source));
  final position = createRelativePositionFromTypeIndex(text, 2);
  final resolved = createAbsolutePositionFromRelativePosition(
    decodeRelativePosition(encodeRelativePosition(position)),
    doc,
  );

  stdout.writeln('relative:index=${resolved?.index};assoc=${resolved?.assoc}');
}

Doc _docWithTextRoot(String text) {
  final doc = Doc(clientId: ClientId(1));
  doc.getText('body').insertText(0, text);
  return doc;
}
