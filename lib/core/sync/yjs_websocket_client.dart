import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'sync_state.dart';

const int _kMaxPendingUpdates = 1000;
const Duration _kIdleTimeout = Duration(minutes: 5);

class YjsWebSocketClient {
  YjsWebSocketClient({
    required Stream<Uint8List> stream,
    required StreamSink<dynamic> sink,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _stream = stream,
        _sink = sink,
        _doc = doc,
        _notifier = notifier;

  final Stream<Uint8List> _stream;
  final StreamSink<dynamic> _sink;
  final Doc _doc;
  final SyncStateNotifier? _notifier;

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
    _sub = _stream.listen(_handleMessage);
    _isConnected = true;
    debugPrint('[YjsWS] connect: sending Step1 elapsed=${sw.elapsedMilliseconds}ms');
    _sendStep1(_doc);
    _resetIdleTimer();
    debugPrint('[YjsWS] connect DONE elapsed=${sw.elapsedMilliseconds}ms');
  }

  void _handleMessage(Uint8List data) {
    if (data.isEmpty) return;
    final sw = Stopwatch()..start();
    final decoder = createDecoder(data);
    final encoder = createEncoder();
    final msgType = readSyncMessage(decoder, encoder, _doc, 'remote');
    debugPrint('[YjsWS] _handleMessage msgType=$msgType dataLen=${data.length} elapsed=${sw.elapsedMilliseconds}ms');
    switch (msgType) {
      case messageSyncStep1:
        final step2 = toUint8Array(encoder);
        _sendRaw(step2);
        if (!_handshakeDone) {
          _handshakeDone = true;
          debugPrint('[YjsWS] HANDSHAKE DONE (via Step1) elapsed=${sw.elapsedMilliseconds}ms');
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
      case messageSyncStep2:
        if (!_handshakeDone) {
          _handshakeDone = true;
          debugPrint('[YjsWS] HANDSHAKE DONE (via Step2) elapsed=${sw.elapsedMilliseconds}ms');
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
        _onUpdateController.add(data);
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

  void _sendRaw(Uint8List bytes) => _sink.add(bytes);

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
    _isConnected = false;
    _handshakeDone = false;
    debugPrint('[YjsWS] disconnect DONE');
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await disconnect();
   