import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crdt_lf/crdt_lf.dart';

void main() {
  test('Dumb Go Relay sync and convergence verification', () async {
    final exeExtension = Platform.isWindows ? '.exe' : '';
    final binaryName = 'crdt_relay$exeExtension';
    final binaryPath = Platform.isWindows ? binaryName : './$binaryName';

    // 1. Compile Go server
    final compileResult = await Process.run(
      'go',
      ['build', '-o', binaryName, './backend/cmd/crdt_relay/main.go'],
    );
    if (compileResult.exitCode != 0) {
      fail('Failed to compile Go relay: ${compileResult.stderr}');
    }

    // Spawn the compiled Go server process
    final process = await Process.start(binaryPath, []);

    // Register server cleanups
    addTearDown(() async {
      process.kill();
      await process.exitCode;
      try {
        final file = File(binaryName);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    });

    final serverStarted = Completer<void>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print('GO STDOUT: $line');
      if (line.contains('Relay server listening on :8989')) {
        if (!serverStarted.isCompleted) {
          serverStarted.complete();
        }
      }
    });

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print('GO STDERR: $line');
    });

    await serverStarted.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Go server did not start in time'),
    );

    final docs = <String, CRDTDocument>{};
    final sockets = <String, WebSocket>{};

    // Helper to setup client
    Future<CRDTDocument> setupClient(String name, PeerId peerId) async {
      final doc = CRDTDocument(peerId: peerId)..registerDefaultFactories();
      final ws = await WebSocket.connect('ws://localhost:8989/sync');
      addTearDown(() => ws.close());
      
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

    // Helper for polling
    Future<void> waitFor(bool Function() condition, {String message = 'Condition timed out'}) async {
      final timeout = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(timeout)) {
          throw TimeoutException(message);
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }

    final peerA = PeerId.parse('00000000-0000-4000-8000-000000000001');
    final peerB = PeerId.parse('00000000-0000-4000-8000-000000000002');

    final docA = await setupClient('A', peerA);
    final docB = await setupClient('B', peerB);

    final textA = docA.registeredHandlers['text-relay']! as CRDTFugueTextHandler;
    final textB = docB.registeredHandlers['text-relay']! as CRDTFugueTextHandler;

    // Type initial text on A and sync
    textA.insert(0, "Hello");
    sockets['A']!.add(docA.binaryExportChanges());

    // Wait for sync propagation dynamically
    await waitFor(() => textB.value == "Hello", message: "Client B failed to receive initial text 'Hello'");

    // Concurrent edits
    textA.insert(5, " Ola");
    textB.insert(5, " World");

    // Export changes concurrently
    sockets['A']!.add(docA.binaryExportChanges());
    sockets['B']!.add(docB.binaryExportChanges());

    // Wait for sync propagation and convergence dynamically
    await waitFor(() => textA.value == textB.value, message: "Documents A and B did not converge");

    // Assert that both documents have converged to the exact same text and it matches one of the valid outcomes
    expect(textA.value, textB.value);
    expect(textA.value, anyOf('Hello Ola World', 'Hello World Ola'));
  });
}
