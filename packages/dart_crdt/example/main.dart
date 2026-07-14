import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final text = doc.getText('body');

  text.insertText(0, 'Hello, local-first Dart.');

  stdout.writeln('main:text=${text.toPlainText()};package=$packageName');
}
