import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dart_crdt/dart_crdt.dart';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'sync_state.dart';

const int _kMaxPendingUpdates = 1000;
const Duration _kIdleTimeout = Duration(minutes: 5);

typedef ChannelBuilder = Future<WebSocketChannel> Function();

// ---- Yjs wire-protocol helpers (7-bit varUint encoding) ----

(int, int) _readVarUint(Uint8List data, int offset) {
  int value = 0;
  int shift = 0;
  int i = offset;
  while (i < data.length) {
    final byte = data[i];
    i++;
    value |= (byte & 127) << shift;
    shift += 7;
    if ((byte & 128) == 0) return (value, i - offset);
  }
  throw FormatException('Unexpected end of data in varint');
}

(int, Uint8List) _readVarUint8Array(Uint8List data, int offset) {
  final (length, lenSize) = _readVarUint(data, offset);
  final start = offset + lenSize;
  if (start + length > data.length) {
    throw FormatException('Unexpected end of data in varuint8array');
  }
  return (length, data.sublist(start, start + length));
}

List<int> _encodeVarUint(int value) {
  final bytes = <int>[];
  while (value > 127) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  bytes.add(value & 127);
  return bytes;
}

Uint8List _encodeMessage(int type, List<int> payload) {
  final typeBytes = _encodeVarUint(type);
  final payloadLen = _encodeVarUint(payload.length);
  final result = Uint8List(typeBytes.length + payloadLen.length + payload.length);
  result.setRange(0, typeBytes.length, typeBytes);
  result.setRange(typeBytes.length, typeBytes.length + payloadLen.length, payloadLen);
  result.setRange(typeBytes.length + payloadLen.length, result.length, payload);
  return result;
}

class YjsWebSocketClient {
  YjsWebSocketClient({
    required this.channelBuilder,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _doc = doc,
        _notifier = notifier;

  final ChannelBuilder channelBuilder;
  final Doc _doc;
  final SyncStateNotifier? _notifier;

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
      final (msgType, typeSize) = _readVarUint(data, 0);
      debugPrint('[YjsWS] _handleMessage msgType=$msgType dataLen=${data.length} elapsed=${sw.elapsedMilliseconds}ms');
      switch (msgType) {
        case 0: // messageSyncStep1 — server sent state vector
          final (_, svBytes) = _readVarUint8Array(data, typeSize);
          final missing = encodeStateAsUpdate(_doc, svBytes);
          final step2 = _encodeMessage(1, missing);
          _sendRaw(step2);
          if (!_handshakeDone) {
            _handshakeDone = true;
            debugPrint('[YjsWS] HANDSHAKE DONE (via Step1) elapsed=${sw.elapsedMilliseconds}ms');
            _notifier?.markSynced(DateTime.now());
            _flushPending();
          }
        case 1: // messageSyncStep2 — server sent update (from our Step1)
          final (_, updateBytes) = _readVarUint8Array(data, typeSize);
          applyUpdate(_doc, updateBytes);
          if (!_handshakeDone) {
            _handshakeDone = true;
            debugPrint('[YjsWS] HANDSHAKE DONE (via Step2) elapsed=${sw.elapsedMilliseconds}ms');
            _notifier?.markSynced(DateTime.now());
            _flushPending();
          }
          _onUpdateController.add(data);
        case 2: // messageYjsUpdate — raw update broadcast
          final (_, updateBytes) = _readVarUint8Array(data, typeSize);
          applyUpdate(_doc, updateBytes);
          _onUpdateController.add(data);
        default:
          dev.log('[YjsWS] Unknown sync message type: $msgType', name: 'YjsWS');
      }
    } catch (e) {
      dev.log('[YjsWS] Error handling message: $e', name: 'YjsWS');
    }
    _resetIdleTimer();
  }

  void _sendStep1() {
    final sv = encodeDocumentStateVector(_doc);
    final msg = _encodeMessage(0, sv);
    _sendRaw(msg);
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
    final framed = _encodeMessage(2, update);
    if (!_isConnected) {
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
    _idleTimer = Timer(_kIdleTimeout, disconnect);
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
