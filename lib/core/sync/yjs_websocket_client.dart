import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'sync_state.dart';

const Duration _kIdleTimeout = Duration(minutes: 5);

class YjsWebSocketClient {
  YjsWebSocketClient({
    required String baseUrl,
    required String authToken,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _baseUrl = baseUrl,
        _authToken = authToken,
        _doc = doc,
        _notifier = notifier;

  YjsWebSocketClient.forTest({
    required Stream<Uint8List> channelStream,
    required StreamSink<Uint8List> channelSink,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _fakeStream = channelStream,
        _fakeSink = channelSink,
        _doc = doc,
        _notifier = notifier;

  String? _baseUrl;
  String? _authToken;
  Stream<Uint8List>? _fakeStream;
  StreamSink<Uint8List>? _fakeSink;
  final Doc _doc;
  final SyncStateNotifier? _notifier;

  IOWebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _sub;
  StreamSink<dynamic>? _sink;
  final StreamController<Uint8List> _onUpdateController =
      StreamController<Uint8List>.broadcast();
  Timer? _idleTimer;
  bool _isConnected = false;
  bool _handshakeDone = false;
  final List<Uint8List> _pendingUpdates = [];

  Stream<Uint8List> get onUpdate => _onUpdateController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String noteId) async {
    await disconnect();
    _handshakeDone = false;
    _notifier?.markSyncing();

    if (_fakeStream != null && _fakeSink != null) {
      _sub = _fakeStream!.listen(_handleMessage);
      _sink = _fakeSink;
    } else {
      final uri = Uri.parse('$_baseUrl/api/v1/sync/ws/$noteId');
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      _sub = _channel!.stream
          .where((m) => m is List<int>)
          .map((m) => Uint8List.fromList(m as List<int>))
          .listen(_handleMessage);
      _sink = _channel!.sink;
    }
    _isConnected = true;
    _sendStep1(_doc);
    _resetIdleTimer();
  }

  void _handleMessage(Uint8List data) {
    if (data.isEmpty) return;
    final decoder = createDecoder(data);
    final encoder = createEncoder();
    final msgType = readSyncMessage(decoder, encoder, _doc, 'remote');
    switch (msgType) {
      case messageSyncStep1:
        final step2 = toUint8Array(encoder);
        _sendRaw(step2);
        if (!_handshakeDone) {
          _handshakeDone = true;
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
      case messageSyncStep2:
        if (!_handshakeDone) {
          _handshakeDone = true;
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
      case messageYjsUpdate:
        _onUpdateController.add(data);
      default:
        dev.log('[YjsWS] Unknown sync message type: $msgType', name: 'YjsWS');
    }
    _resetIdleTimer();
  }

  void _sendStep1(Doc doc) {
    final enc = createEncoder();
    writeSyncStep1(enc, doc);
    _sendRaw(toUint8Array(enc));
  }

  void _sendRaw(Uint8List bytes) => _sink?.add(bytes);

  void _flushPending() {
    if (_pendingUpdates.isEmpty) return;
    for (final u in _pendingUpdates) {
      _sendRaw(u);
    }
    _pendingUpdates.clear();
  }

  void sendUpdate(Uint8List update) {
    final enc = createEncoder();
    writeUpdate(enc, update);
    final framed = toUint8Array(enc);
    if (!_isConnected) {
      _pendingUpdates.add(framed);
      return;
    }
    _sendRaw(framed);
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, disconnect);
  }

  Future<void> disconnect() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _sink = null;
    _isConnected = false;
    _handshakeDone = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _onUpdateController.close();
  }
}
