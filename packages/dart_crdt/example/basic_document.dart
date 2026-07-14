import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc(guid: 'example-basic', clientId: ClientId(1));
  final text = doc.getText('body');
  final items = doc.getArray('items');
  final settings = doc.get('settings');

  text.insertText(0, 'Hello, local-first Dart.');
  items
    ..push('task-1')
    ..push('task-2');
  settings.setAttr('theme', 'light');

  stdout.writeln(
    'basic:text=${text.toPlainText()};'
    'items=${items.toArray().join(',')};'
    'theme=${settings.getAttr('theme')}',
  );
}
