import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/sync/yjs_websocket_client.dart';

void main() {
  test('client sends SyncStep1 on connect', () async {
    final channelPair = _FakeChannelPair();
    final clientDoc = Doc();
    final client = YjsWebSocketClient(
      stream: channelPair.clientIncoming,
      sink: channelPair.clientOutgoing,
      doc: clientDoc,
    );

    final serverIncoming = <Uint8List>[];
    channelPair.serverIncoming.listen(serverIncoming.add);

    await client.connect('note-1');
    await Future<void>.delayed(Duration.zero);

    expect(serverIncoming.length, 1);
    // First byte should be 0 (messageSyncStep1).
    expect(serverIncoming.first[0], 0);
  });

  test('client applies incoming SyncStep2 and completes handshake', () async {
    final serverDoc = Doc();
    // Pre-create YText before transact to work around yjs_dart type bug.
    serverDoc.getText('content_x');
    serverDoc.transact((txn) {
      serverDoc.getText('content_x')!.insert(0, 'server text');
    });

    final channelPair = _FakeChannelPair();
    final clientDoc = Doc();
    // Pre-create matching YText so applyUpdate can populate it.
    clientDoc.getText('content_x');

    final client = YjsWebSocketClient(
      stream: channelPair.clientIncoming,
      sink: channelPair.clientOutgoing,
      doc: clientDoc,
    );

    final serverIncoming = <Uint8List>[];
    channelPair.serverIncoming.listen(serverIncoming.add);

    await client.connect('note-1');
    await Future<void>.delayed(Duration.zero);

    // Server received client's Step1 — respond with Step2.
    final svBytes = serverIncoming.first;
    final step2Enc = createEncoder();
    writeSyncStep2(step2Enc, serverDoc, svBytes);
    channelPair.serverOutgoing.add(toUint8Array(step2Enc));

    await Future<void>.delayed(Duration.zero);

    expect(clientDoc.getText('content_x')!.toString(), 'server text');
  });
}

class _FakeChannelPair {
  final serverToClient = StreamController<Uint8List>.broadcast();
  final clientToServer = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get clientIncoming => serverToClient.stream;
  StreamSink<Uint8List> get clientOutgoing => clientToServer.sink;
  StreamSink<Uint8List> get serverOutgoing => serverToClient.sink;
  Stream<Uint8List> get serverIncoming => clientToServer.stream;
}
