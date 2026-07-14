import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:dart_crdt/dart_crdt.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_state.dart';
import 'yjs_sync_protocol_codec.dart';

const int _kMaxPendingUpdates = 1000;
const Duration _kIdleTimeout = Duration(minutes: 5);

typedef ChannelBuilder = Future<WebSocketChannel> Function();

class YjsWebSocketClient {
  YjsWebSocketClient({
    required this.channelBuilder,
    required Doc doc,
    SyncStateNotifier? notifier,
    void Function()? onIdleDisconnect,
  })  : _doc = doc,
        _notifier = notifier,
        _onIdleDisconnect = onIdleDisconnect;

  final ChannelBuilder channelBuilder;
  final Doc _doc;
  final SyncStateNotifier? _notifier;
  final void Function()? _onIdleDisconnect;

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _sub;
  final StreamController<Uint8List> _onUpdateController =
      StreamController<Uint8List>.broadcast();
  Timer? _idleTimer;
  bool _isConnected = false;
  bool _handshakeDone = false;
  final List<Uint8List> _pendingUpdates = [];
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _connectedNoteId;

  Stream<Uint8List> get onUpdate => _onUpdateController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String noteId) async {
    final sw = Stopwatch()..start();
    debugPrint('[YjsWS] connect START noteId=$noteId');
    await disconnect();
    _reconnectAttempts = 0;
    _connectedNoteId = noteId;
    _handshakeDone = false;
    _notifier?.markSyncing();

    try {
      _channel = await channelBuilder();
      final stream = _channel!.stream
          .where((m) => m is List<int>)
          .map((m) => Uint8List.fromList(m as List<int>));
      _sub = stream.listen(
        _handleMessage,
        onError: (e) {
          debugPrint('[YjsWS] connection error: $e');
          _isConnected = false;
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[YjsWS] connection closed');
          _isConnected = false;
          _scheduleReconnect();
        },
      );
      _isConnected = true;
      debugPrint('[YjsWS] connect: sending Step1 elapsed=${sw.elapsedMilliseconds}ms');
      _sendStep1();
      _resetIdleTimer();
      debugPrint('[YjsWS] connect DONE elapsed=${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[YjsWS] connect FAIL: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _handleMessage(Uint8List data) {
    if (data.isEmpty) return;
    final sw = Stopwatch()..start();
    try {
      final (msgType, payload) = YjsSyncProtocolCodec.decode(data);
      debugPrint('[YjsWS] _handleMessage msgType=$msgType dataLen=${data.length} elapsed=${sw.elapsedMilliseconds}ms');
      switch (msgType) {
        case YjsSyncProtocolCodec.messageSyncStep1:
          final step2 = YjsSyncProtocolCodec.encodeStep2(_doc, payload);
          _sendRaw(step2);
          if (!_handshakeDone) {
            _handshakeDone = true;
            debugPrint('[YjsWS] HANDSHAKE DONE (via Step1) elapsed=${sw.elapsedMilliseconds}ms');
            _notifier?.markSynced(DateTime.now());
            _flushPending();
          }
        case YjsSyncProtocolCodec.messageSyncStep2:
          applyUpdate(_doc, payload);
          if (!_handshakeDone) {
            _handshakeDone = true;
            debugPrint('[YjsWS] HANDSHAKE DONE (via Step2) elapsed=${sw.elapsedMilliseconds}ms');
            _notifier?.markSynced(DateTime.now());
            _flushPending();
          }
          _onUpdateController.add(data);
        case YjsSyncProtocolCodec.messageYjsUpdate:
          applyUpdate(_doc, payload);
          _onUpdateController.add(data);
        default:
          dev.log('[YjsWS] Unknown sync message type: $msgType', name: 'YjsWS');
      }
    } catch (e, stackTrace) {
      dev.log('[YjsWS] Error handling message: $e', name: 'YjsWS', error: e, stackTrace: stackTrace);
    }
    _resetIdleTimer();
  }

  void _sendStep1() {
    _sendRaw(YjsSyncProtocolCodec.encodeStep1(_doc));
  }

  void _sendRaw(Uint8List bytes) {
    if (_channel != null) {
      _channel!.sink.add(bytes);
    }
  }

  void _flushPending() {
    if (_pendingUpdates.isEmpty) return;
    for (final u in _pendingUpdates) {
      _sendRaw(u);
    }
    _pendingUpdates.clear();
  }

  void sendUpdate(Uint8List update) {
    _resetIdleTimer();
    debugPrint('[DEBUG-DIAG-EDIT] sendUpdate: connected=$_isConnected updateLen=${update.length}');
    final framed = YjsSyncProtocolCodec.encodeUpdate(update);
    if (!_isConnected || !_handshakeDone) {
      if (_pendingUpdates.length >= _kMaxPendingUpdates) {
        debugPrint('[YjsWS] sendUpdate: pendingUpdates full, dropping oldest (was ${_pendingUpdates.length})');
        _pendingUpdates.removeAt(0);
      }
      _pendingUpdates.add(framed);
      debugPrint('[YjsWS] sendUpdate: queued (pending=${_pendingUpdates.length}, connected=false) updateLen=${update.length}');
      _scheduleReconnect();
      return;
    }
    debugPrint('[YjsWS] sendUpdate: sending directly updateLen=${update.length}');
    _sendRaw(framed);
  }

  void _scheduleReconnect() {
    if (_connectedNoteId == null) return;
    if (_reconnectTimer != null) return;
    _reconnectAttempts++;
    final delay = Duration(
      milliseconds: (500 * (1 << (_reconnectAttempts - 1))).clamp(500, 30000),
    );
    debugPrint('[YjsWS] _scheduleReconnect attempt=$_reconnectAttempts delay=${delay.inMilliseconds}ms noteId=$_connectedNoteId');
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      try {
        debugPrint('[YjsWS] _scheduleReconnect: reconnecting...');
        await connect(_connectedNoteId!);
      } catch (e) {
        debugPrint('[YjsWS] _scheduleReconnect: failed, retrying: $e');
        _scheduleReconnect();
      }
    });
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, () {
      _onIdleDisconnect?.call();
      disconnect();
    });
  }

  Future<void> disconnect() async {
    debugPrint('[YjsWS] disconnect START pending=${_pendingUpdates.length} connected=$_isConnected');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _idleTimer?.cancel();
    _idleTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
    _handshakeDone = false;
    debugPrint('[YjsWS] disconnect DONE');
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await disconnect();
    await _onUpdateController.close();
  }
}
