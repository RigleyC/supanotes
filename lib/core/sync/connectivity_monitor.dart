import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityMonitorProvider = Provider<ConnectivityMonitor>((ref) {
  final monitor = ConnectivityMonitor();
  ref.onDispose(monitor.dispose);
  return monitor;
});

class ConnectivityMonitor {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  bool _isConnected = true;

  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  ConnectivityMonitor() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final isConnected = !results.contains(ConnectivityResult.none);
      if (_isConnected != isConnected) {
        _isConnected = isConnected;
        _controller.add(isConnected);
      }
    })..onError((e) {
      debugPrint('connectivity stream error: $e');
    });

    _connectivity.checkConnectivity().then((results) {
      _isConnected = !results.contains(ConnectivityResult.none);
      _controller.add(_isConnected);
    }).catchError((e) {
      debugPrint('connectivity check error: $e');
    });
  }

  bool get isConnected => _isConnected;
  Stream<bool> get onConnected => _controller.stream.where((connected) => connected);
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void dispose() {
    _connectivitySub.cancel();
    _controller.close();
  }
}
