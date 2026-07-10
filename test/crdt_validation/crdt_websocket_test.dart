import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:supanotes/core/sync/yjs_websocket_client.dart';

void main() {
  test('Teste 4 — Full stack WebSocket Yjs convergência via Go Relay', () async {
    final exeExtension = Platform.isWindows ? '.exe' : '';
    final binaryName = 'crdt_relay$exeExtension';
    
    // Ensure build directory exists
    final buildDir = Directory('build');
    if (!buildDir.existsSync()) {
      buildDir.createSync(recursive: true);
    }
    
    final binaryPath = 'build/$binaryName';

    // 1. Compile Go relay server
    print('Compilando o servidor Go Relay...');
    final compileResult = await Process.run(
      'go',
      ['build', '-o', '../build/$binaryName', './cmd/crdt_relay/main.go'],
      environment: {'GOWORK': 'off'},
      workingDirectory: 'backend',
    );
    if (compileResult.exitCode != 0) {
      fail('Failed to compile Go relay: ${compileResult.stderr}');
    }

    // Spawn the compiled Go server process
    print('Iniciando o servidor Go Relay...');
    final process = await Process.start(binaryPath, []);

    // Register server cleanups using addTearDown
    addTearDown(() async {
      process.kill();
      await process.exitCode;
      try {
        final file = File(binaryPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    });

    final serverStarted = Completer<void>();

    // Fail early if the Go process exits before print
    process.exitCode.then((code) {
      if (!serverStarted.isCompleted) {
        serverStarted.completeError(
          ProcessException(binaryPath, [], 'Go server exited early with code $code'),
        );
      }
    });

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

    // Wait dynamically for server to startup
    await serverStarted.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Go server did not start in time'),
    );

    // 2. Setup Yjs clients connected via WebSocket
    final docA = Doc();
    final docB = Doc();
    final textA = docA.getText('content')!;
    final textB = docB.getText('content')!;

    // Create client A
    final clientA = YjsWebSocketClient(
      channelBuilder: () async {
        return WebSocketChannel.connect(Uri.parse('ws://localhost:8989/sync'));
      },
      doc: docA,
    );

    // Create clientB
    final clientB = YjsWebSocketClient(
      channelBuilder: () async {
        return WebSocketChannel.connect(Uri.parse('ws://localhost:8989/sync'));
      },
      doc: docB,
    );

    // Listen to local document updates and forward them via WebSocket
    docA.on('update', (dynamic update, dynamic origin, dynamic doc, dynamic transaction) {
      if (origin != 'remote') {
        clientA.sendUpdate(update as Uint8List);
      }
    });

    docB.on('update', (dynamic update, dynamic origin, dynamic doc, dynamic transaction) {
      if (origin != 'remote') {
        clientB.sendUpdate(update as Uint8List);
      }
    });

    // Connect clients
    print('Conectando os clientes via WebSocket...');
    await clientA.connect('note-ws-test');
    await clientB.connect('note-ws-test');

    // Wait a brief moment for initial handshake
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Helper for polling condition
    Future<void> waitFor(
      bool Function() condition, {
      String message = 'Condition timed out',
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final stopwatch = Stopwatch()..start();
      while (!condition()) {
        if (stopwatch.elapsed > timeout) {
          throw TimeoutException(message);
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }

    // Insert initial text on Client A
    print('Inserindo texto inicial no Cliente A...');
    docA.transact((_) {
      textA.insert(0, 'hello world');
    });

    // Wait for propagation to Client B
    await waitFor(
      () => textB.toString() == 'hello world',
      message: "Cliente B não recebeu o texto inicial 'hello world'. Atual: '${textB.toString()}'",
    );
    print('Texto inicial propagado com sucesso!');

    // Concurrent edits
    print('Aplicando edições concorrentes...');
    docA.transact((_) {
      textA.insert(5, 'XXX');
    });
    docB.transact((_) {
      textB.insert(3, 'YYY');
    });

    // Wait for convergence
    await waitFor(
      () => textA.toString() == textB.toString(),
      message: "Os documentos A e B não convergiram. A: '${textA.toString()}', B: '${textB.toString()}'",
    );

    final finalResult = textA.toString();
    print('✅ Convergência atingida via WebSocket: "$finalResult"');

    expect(finalResult, equals('helYYYloXXX world'));
    
    // Clean up
    await clientA.disconnect();
    await clientB.disconnect();
  });
}
