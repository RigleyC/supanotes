import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crdt_lf/crdt_lf.dart';

void main() {
  test('Dumb Go Relay sync and convergence verification', () async {
    // 1. Spawn Go server process
    final process = await Process.start(
      'go',
      ['run', 'backend/cmd/crdt_relay/main.go'],
    );

    // Forward Go server output
    process.stdout.transform(utf8.decoder).listen((data) {
      print('GO STDOUT: $data');
    });
    process.stderr.transform(utf8.decoder).listen((data) {
      print('GO STDERR: $data');
    });

    // Wait 2 seconds for the server to boot up and bind to :8989
    await Future.delayed(const Duration(milliseconds: 2000));

    final docs = <String, CRDTDocument>{};
    final sockets = <String, WebSocket>{};

    // Helper to setup client
    Future<CRDTDocument> setupClient(String name, PeerId peerId) async {
      final doc = CRDTDocument(peerId: peerId)..registerDefaultFactories();
      final ws = await WebSocket.connect('ws://localhost:8989/sync');
      
      sockets[name] = ws;
      docs[name] = doc;

      // Auto-instantiate the Fugue text handler
      CRDTFugueTextHandler(doc, 'text-relay');

      ws.listen((data) {
        if (data is List<int>) {
          doc.binaryImportChanges(Uint8List.fromList(data));
        }
      });

      return doc;
    }

    try {
      final peerA = PeerId.parse('00000000-0000-4000-8000-000000000001');
      final peerB = PeerId.parse('00000000-0000-4000-8000-000000000002');

      final docA = await setupClient('A', peerA);
      final docB = await setupClient('B', peerB);

      final textA = docA.registeredHandlers['text-relay']! as CRDTFugueTextHandler;
      final textB = docB.registeredHandlers['text-relay']! as CRDTFugueTextHandler;

      // Type initial text on A and sync
      textA.insert(0, "Hello");
      sockets['A']!.add(docA.binaryExportChanges());

      // Wait for sync propagation
      await Future.delayed(const Duration(milliseconds: 250));
      expect(textB.value, "Hello");

      // Concurrent edits
      textA.insert(5, " Ola");
      textB.insert(5, " World");

      // Export changes concurrently
      sockets['A']!.add(docA.binaryExportChanges());
      sockets['B']!.add(docB.binaryExportChanges());

      // Wait for sync propagation
      await Future.delayed(const Duration(milliseconds: 400));

      // Assert that both documents have converged to the exact same text
      expect(textA.value, textB.value);
      expect(textA.value, anyOf('Hello Ola World', 'Hello World Ola'));
    } finally {
      // Close sockets and kill server
      for (final ws in sockets.values) {
        await ws.close();
      }
      process.kill();
    }
  });
}
