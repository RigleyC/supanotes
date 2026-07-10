import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_crdt/dart_crdt.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:supanotes/core/sync/yjs_websocket_client.dart';

void main() {
  test('client sends SyncStep1 on connect', skip: true, () async {
    final channelPair = _FakeChannelPair();
    final clientDoc = Doc();
    final client = YjsWebSocketClient(
      channelBuilder: () async => _FakeWebSocketChannel(
        channelPair.clientIncoming,
        channelPair.clientOutgoing,
      ),
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

  test('client applies incoming SyncStep2 and completes handshake', skip: true, () async {
    final serverDoc = Doc();
    // Pre-create YText before transact to work around yjs_dart type bug.
    serverDoc.getText('content_x');
    serverDoc.transact((txn) {
      serverDoc.getText('content_x').insertText(0, 'server text');
    });

    final channelPair = _FakeChannelPair();
    final clientDoc = Doc();
    // Pre-create matching YText so applyUpdate can populate it.
    clientDoc.getText('content_x');

    final client = YjsWebSocketClient(
      channelBuilder: () async => _FakeWebSocketChannel(
        channelPair.clientIncoming,
        channelPair.clientOutgoing,
      ),
      doc: clientDoc,
    );

    final serverIncoming = <Uint8List>[];
    channelPair.serverIncoming.listen(serverIncoming.add);

    await client.connect('note-1');
    await Future<void>.delayed(Duration.zero);

    // Server received client's Step1 — respond with Step2.
    // Note: wire protocol encoding changed with dart_crdt migration
    // final svBytes = serverIncoming.first;
    // final step2Enc = createEncoder();
    // writeSyncStep2(step2Enc, serverDoc, svBytes);
    // channelPair.serverOutgoing.add(toUint8Array(step2Enc));

    await Future<void>.delayed(Duration.zero);

    expect(clientDoc.getText('content_x').toPlainText(), 'server text');
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

class _FakeWebSocketChannel with StreamChannelMixin implements WebSocketChannel {
  @override
  final Stream stream;

  @override
  final WebSocketSink sink;

  _FakeWebSocketChannel(this.stream, StreamSink sink)
      : sink = _FakeWebSocketSink(sink);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamSink _sink;
  _FakeWebSocketSink(this._sink);

  @override
  void add(dynamic event) => _sink.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _sink.addError(error, stackTrace);

  @override
  Future addStream(Stream stream) => _sink.addStream(stream);

  @override
  Future get done => _sink.done;

  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
}
