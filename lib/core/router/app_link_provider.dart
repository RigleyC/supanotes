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
  AppLinkStream(
    this.source, {
    this.deduplicationDuration = const Duration(seconds: 1),
  });

  final AppLinkSource source;
  final Duration deduplicationDuration;

  Stream<Uri> stream() {
    final controller = StreamController<Uri>();
    StreamSubscription<Uri>? subscription;
    Timer? deduplicationWindow;
    String? lastPath;
    var closed = false;

    void emit(Uri uri) {
      if (closed || !isShareLinkUri(uri)) return;
      if (uri.path == lastPath && deduplicationWindow != null) return;
      lastPath = uri.path;
      deduplicationWindow?.cancel();
      deduplicationWindow = Timer(deduplicationDuration, () {
        deduplicationWindow = null;
      });
      controller.add(uri);
    }

    void emitError(Object error, StackTrace stack) {
      if (!closed) controller.addError(error, stack);
    }

    try {
      subscription = source.uriLinkStream.listen(
        emit,
        onError: (Object error, StackTrace stack) => emitError(error, stack),
        onDone: () {
          if (!closed) {
            closed = true;
            controller.close();
          }
        },
      );
    } catch (error, stack) {
      emitError(error, stack);
    }

    source.getInitialLink().then((uri) {
      if (uri != null) emit(uri);
    }, onError: (Object error, StackTrace stack) => emitError(error, stack));

    controller.onCancel = () async {
      closed = true;
      deduplicationWindow?.cancel();
      await subscription?.cancel();
      await controller.close();
    };
    return controller.stream;
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
