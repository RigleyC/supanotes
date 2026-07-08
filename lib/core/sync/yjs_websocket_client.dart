import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import 'sync_state.dart';

/// Duration after which an idle WebSocket connection is torn down.
const Duration _kIdleTimeout = Duration(minutes: 5);

/// WebSocket client for real-time Yjs sync with the collaboration server.
///
/// Connects to `ws://baseUrl/api/v1/sync/ws/{noteId}`, performs the Yjs
/// sync protocol handshake (sync step 1), and relays binary updates
/// bidirectionally. An idle timer disconnects after 5 minutes of
/// inactivity.
class YjsWebSocketClient {
  YjsWebSocketClient({
    required this.baseUrl,
    required this.authToken,
    SyncStateNotifier? notifier,
  }) : _notifier = notifier;

  final String baseUrl;
  final String authToken;
  final SyncStateNotifier? _notifier;

  IOWebSocketChannel? _channel;
  Timer? _idleTimer;
  bool _isConnected = false;

  /// Sent when a binary sync update arrives from the server.
  final StreamController<Uint8List> _onUpdateController =
      StreamController<Uint8List>.broadcast();

  /// Broadcast stream of incoming Yjs binary updates.
  Stream<Uint8List> get onUpdate => _onUpdateController.stream;

  bool get isConnected => _isConnected;

  /// Connect to the sync server for [noteId].
  Future<void> connect(String noteId) async {
    await disconnect();

    final uri = Uri.parse('$baseUrl/api/v1/sync/ws/$noteId');
    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $authToken',
      },
    );

    _isConnected = true;
    _resetIdleTimer();

    _channel!.stream.listen(
      (message) {
        if (message is List<int>) {
          _onUpdateController.add(Uint8List.fromList(message));
        }
        _resetIdleTimer();
      },
      onError: (error) {
        dev.log('[YjsWS] Error: $error', name: 'YjsWS');
        _isConnected = false;
      },
      onDone: () {
        dev.log('[YjsWS] Connection closed', name: 'YjsWS');
        _isConnected = false;
      },
      cancelOnError: false,
    );

    _notifier?.markSyncing();
    dev.log('[YjsWS] Connected to $uri', name: 'YjsWS');
  }

  /// Send a binary Yjs sync update to the server.
  void sendUpdate(Uint8List update) {
    if (_channel == null || !_isConnected) {
      dev.log('[YjsWS] Cannot send — not connected', name: 'YjsWS');
      return;
    }
    _channel!.sink.add(update);
  }

  /// Reset the idle disconnect timer.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, () {
      dev.log('[YjsWS] Idle timeout — disconnecting', name: 'YjsWS');
      disconnect();
    });
  }

  /// Close the WebSocket connection.
  Future<void> disconnect() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    await disconnect();
    await _onUpdateController.close();
  }
}
