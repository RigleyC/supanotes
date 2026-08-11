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

  Stream<Uri> stream() {
    final controller = StreamController<Uri>();
    StreamSubscription<Uri>? subscription;
    final bufferedRuntimeLinks = <Uri>[];
    String? initialPath;
    var initialResolved = false;
    var initialEchoPending = false;
    var closed = false;

    void emit(Uri uri) {
      if (closed || !isShareLinkUri(uri)) return;
      controller.add(uri);
    }

    void emitError(Object error, StackTrace stack) {
      if (!closed) controller.addError(error, stack);
    }

    void emitRuntime(Uri uri) {
      if (closed || !isShareLinkUri(uri)) return;
      // app_links can emit the initial URI again through the runtime stream.
      // Suppress only that one known echo. Every later event is a deliberate
      // open, including opening the same path again after an error or login.
      if (initialEchoPending && uri.path == initialPath) {
        initialEchoPending = false;
        return;
      }
      emit(uri);
    }

    void flushBufferedRuntimeLinks() {
      final pending = List<Uri>.of(bufferedRuntimeLinks);
      bufferedRuntimeLinks.clear();
      for (final uri in pending) {
        emitRuntime(uri);
      }
    }

    try {
      subscription = source.uriLinkStream.listen(
        (uri) {
          if (!initialResolved) {
            bufferedRuntimeLinks.add(uri);
            return;
          }
          emitRuntime(uri);
        },
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

    source.getInitialLink().then(
      (uri) {
        if (closed) return;
        initialResolved = true;
        if (uri != null && isShareLinkUri(uri)) {
          initialPath = uri.path;
          initialEchoPending = true;
          emit(uri);
        }
        flushBufferedRuntimeLinks();
      },
      onError: (Object error, StackTrace stack) {
        if (closed) return;
        initialResolved = true;
        flushBufferedRuntimeLinks();
        emitError(error, stack);
      },
    );

    controller.onCancel = () async {
      closed = true;
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
