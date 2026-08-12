import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AppLinkSource {
  Stream<Uri> get uriLinkStream;

  Future<Uri?> getInitialLink();
}

final class _PlatformAppLinkSource implements AppLinkSource {
  _PlatformAppLinkSource() : _links = AppLinks();

  final AppLinks _links;

  @override
  Stream<Uri> get uriLinkStream => _links.uriLinkStream;

  @override
  Future<Uri?> getInitialLink() => _links.getInitialLink();
}

/// Merges the initial link and runtime links into one deduplicated stream.
///
/// A single stream owns the platform subscription. Cancelling the stream
/// cancels that subscription, which prevents duplicate listeners when the
/// provider is rebuilt or disposed.
final class AppLinkStream {
  AppLinkStream(this.source);

  final AppLinkSource source;

  Stream<Uri> stream() => _AppLinkStreamController(source).build();
}

final class _AppLinkStreamController {
  _AppLinkStreamController(this.source);

  final AppLinkSource source;
  final _controller = StreamController<Uri>();
  final _bufferedRuntimeLinks = <Uri>[];
  StreamSubscription<Uri>? _subscription;
  String? _initialPath;
  var _initialResolved = false;
  var _initialEchoPending = false;
  var _closed = false;

  Stream<Uri> build() {
    _listenToRuntimeLinks();
    _resolveInitialLink();
    _controller.onCancel = _cancel;
    return _controller.stream;
  }

  void _listenToRuntimeLinks() {
    try {
      _subscription = source.uriLinkStream.listen(
        _handleRuntimeLink,
        onError: _handleRuntimeError,
        onDone: _handleRuntimeDone,
      );
    } catch (error, stack) {
      _emitError(error, stack);
    }
  }

  void _handleRuntimeLink(Uri uri) {
    if (!_initialResolved) {
      _bufferedRuntimeLinks.add(uri);
      return;
    }
    _emitRuntime(uri);
  }

  void _handleRuntimeError(Object error, StackTrace stack) {
    _emitError(error, stack);
  }

  void _handleRuntimeDone() {
    if (_closed) return;
    _closed = true;
    _controller.close();
  }

  void _resolveInitialLink() {
    source.getInitialLink().then(
      _handleInitialLink,
      onError: _handleInitialLinkError,
    );
  }

  void _handleInitialLink(Uri? uri) {
    if (_closed) return;
    _initialResolved = true;
    if (uri != null && isShareLinkUri(uri)) {
      _initialPath = uri.path;
      _initialEchoPending = true;
      _emit(uri);
    }
    _flushBufferedRuntimeLinks();
  }

  void _handleInitialLinkError(Object error, StackTrace stack) {
    if (_closed) return;
    _initialResolved = true;
    _flushBufferedRuntimeLinks();
    _emitError(error, stack);
  }

  void _emitRuntime(Uri uri) {
    if (_closed || !isShareLinkUri(uri)) return;
    // app_links can emit the initial URI again through the runtime stream.
    // Suppress only that one known echo. Every later event is a deliberate
    // open, including opening the same path again after an error or login.
    if (_initialEchoPending && uri.path == _initialPath) {
      _initialEchoPending = false;
      return;
    }
    _emit(uri);
  }

  void _flushBufferedRuntimeLinks() {
    final pending = List<Uri>.of(_bufferedRuntimeLinks);
    _bufferedRuntimeLinks.clear();
    for (final uri in pending) {
      _emitRuntime(uri);
    }
  }

  void _emit(Uri uri) {
    if (_closed || !isShareLinkUri(uri)) return;
    _controller.add(uri);
  }

  void _emitError(Object error, StackTrace stack) {
    if (!_closed) _controller.addError(error, stack);
  }

  Future<void> _cancel() async {
    _closed = true;
    await _subscription?.cancel();
    await _controller.close();
  }
}

bool isShareLinkUri(Uri uri) {
  final segments = uri.pathSegments;
  return segments.length == 2 &&
      segments.first == 's' &&
      segments.last.isNotEmpty;
}

final appLinkProvider = StreamProvider.autoDispose<Uri>((ref) {
  return AppLinkStream(_PlatformAppLinkSource()).stream();
});
