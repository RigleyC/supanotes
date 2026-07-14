import 'dart:io';

import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final local = Doc(clientId: ClientId(1));
  local.getText('root').insertText(0, 'sync');
  final remote = Doc(clientId: ClientId(9));

  applyUpdate(remote, encodeStateAsUpdate(local));

  stdout.writeln(
    'update:text=${remote.getText('root').toPlainText()};'
    'clock=${remote.store.getClock(ClientId(1)).value}',
  );
}
