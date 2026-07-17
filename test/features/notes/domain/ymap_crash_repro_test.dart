import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

void main() {
  test('YMap vs YText crash reproduction', () {
    final doc1 = Doc();
    doc1.getMap<Object>('nodes');
    doc1.getMap<String>('tasks');
    final ytext = doc1.getText('content/7fe6dde5-23f6-4980-828f-c88a9726871b');
    // Important: yjs_dart doesn't serialize empty shared types. We need to insert text.
    ytext!.insert(0, 'Hello Task');

    final update = encodeStateAsUpdate(doc1);

    final doc2 = Doc();
    // Use applyUpdate which triggers Dynamic Root Type Migration
    applyUpdate(doc2, update);

    // If applyUpdateSafe fails to pre-register, calling getText will throw a CastError 
    // because it was already instantiated as a YMap.
    final ytext2 = doc2.getText('content/7fe6dde5-23f6-4980-828f-c88a9726871b');
    expect(ytext2!.toString(), 'Hello Task');
  });
}
