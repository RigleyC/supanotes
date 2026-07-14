import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final text = doc.getText('body');
  final builder = DeltaBuilder()
    ..insertText(
      text: 'Hello',
      attributes: DeltaAttributes.fromJson({'bold': true}),
    )
    ..insertText(text: '!');

  text.applyDelta(builder.done());

  stdout.writeln(
    'text_delta:text=${text.toPlainText()};'
    'ops=${text.toDelta().operations.length}',
  );
}
