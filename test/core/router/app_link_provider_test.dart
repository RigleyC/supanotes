import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/router/app_link_provider.dart';

class _FakeAppLinkSource implements AppLinkSource {
  final events = StreamController<Uri>();
  Uri? initialLink;
  Object? initialError;
  int initialCalls = 0;

  @override
  Stream<Uri> get uriLinkStream => events.stream;

  @override
  Future<Uri?> getInitialLink() async {
    initialCalls++;
    if (initialError != null) throw initialError!;
    return initialLink;
  }

  Future<void> close() => events.close();
}

void main() {
  test(
    'emits initial and runtime links once, filtering duplicate links',
    () async {
      final source = _FakeAppLinkSource()
        ..initialLink = Uri.parse('https://notes.example/s/token-1');
      addTearDown(source.close);

      final stream = AppLinkStream(
        source,
        deduplicationDuration: const Duration(milliseconds: 1),
      ).stream();
      final values = <Uri>[];
      final subscription = stream.listen(values.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(Duration.zero);
      source.events.add(Uri.parse('https://notes.example/s/token-1'));
      source.events.add(Uri.parse('https://notes.example/s/token-2'));
      source.events.add(Uri.parse('https://notes.example/notes/n-1'));
      await Future<void>.delayed(Duration.zero);

      expect(values.map((value) => value.path), ['/s/token-1', '/s/token-2']);
      expect(source.initialCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      source.events.add(Uri.parse('https://notes.example/s/token-1'));
      await Future<void>.delayed(Duration.zero);
      expect(values.map((value) => value.path), [
        '/s/token-1',
        '/s/token-2',
        '/s/token-1',
      ]);
    },
  );

  test(
    'propagates initial-link errors and cancels the runtime listener',
    () async {
      final source = _FakeAppLinkSource()..initialError = StateError('boom');
      addTearDown(source.close);

      final stream = AppLinkStream(source).stream();
      final errors = <Object>[];
      final subscription = stream.listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(errors.single, isA<StateError>());
    },
  );
}
