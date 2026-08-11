import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_provider.dart';
import 'package:supanotes/features/notes/sharing/application/share_link_access_resolver.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_access_screen.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_reader_screen.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_document.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/sharing/domain/share_link_strings.dart';

import '../../../../helpers/auth_interceptor_test_helper.dart';

ApiClient _testApiClient() {
  final dio = Dio();
  final interceptor = buildTestAuthInterceptor(
    getAccessToken: () async => null,
    getRefreshToken: () async => null,
    saveTokens: ({required accessToken, required refreshToken}) async {},
    onAuthFailure: () async {},
    onRefresh: (_) async => null,
    replay: (options) => dio.fetch<dynamic>(options),
  );
  return ApiClient.test(authInterceptor: interceptor, dio: dio);
}

void main() {
  testWidgets('renders the guest reader with one page shell', (tester) async {
    final router = GoRouter(
      initialLocation: '/s/token',
      routes: [
        GoRoute(
          path: '/s/:token',
          builder: (_, state) =>
              ShareLinkAccessScreen(token: state.pathParameters['token']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    final document = ShareLinkDocument(
      title: 'Public note',
      snapshot: NoteDocumentSnapshot.fromJson(const {
        'schemaVersion': 1,
        'blocks': [
          {
            'id': 'p1',
            'type': 'paragraph',
            'delta': [
              {'insert': 'Hello'},
            ],
            'metadata': {},
          },
        ],
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareLinkAccessProvider('token').overrideWithValue(
            const AsyncData(
              ShareLinkAccessDecision(
                noteId: 'note-1',
                mode: ShareLinkAccessMode.guest,
              ),
            ),
          ),
          shareLinkDocumentProvider(
            'token',
          ).overrideWithValue(AsyncData(document)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Public note'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows hydration errors before opening the editor', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/s/token',
      routes: [
        GoRoute(
          path: '/s/:token',
          builder: (_, state) =>
              ShareLinkAccessScreen(token: state.pathParameters['token']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shareLinkAccessProvider('token').overrideWithValue(
            const AsyncData(
              ShareLinkAccessDecision(
                noteId: 'note-1',
                mode: ShareLinkAccessMode.viewer,
              ),
            ),
          ),
          shareLinkNoteHydrationProvider('token').overrideWithValue(
            AsyncError(StateError('hydrate failed'), StackTrace.current),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text(ShareLinkStrings.accessErrorTitle), findsOneWidget);
  });

  testWidgets('redirects authenticated handoff only after hydration', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/s/token',
      routes: [
        GoRoute(
          path: '/s/:token',
          builder: (_, state) =>
              ShareLinkAccessScreen(token: state.pathParameters['token']!),
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (_, state) => Text('opened ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    const decision = ShareLinkAccessDecision(
      noteId: 'note-1',
      mode: ShareLinkAccessMode.editor,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_testApiClient()),
          shareLinkAccessProvider(
            'token',
          ).overrideWithValue(const AsyncData(decision)),
          shareLinkNoteHydrationProvider(
            'token',
          ).overrideWithValue(const AsyncData<void>(null)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('opened note-1'), findsOneWidget);
  });
}
