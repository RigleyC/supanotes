import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/sharing/data/share_link_repository.dart';
import 'package:supanotes/features/notes/sharing/model/share_link_model.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_section.dart';

class _FakeShareLinkRepository implements IShareLinkRepository {
  _FakeShareLinkRepository(this.current);

  ShareLinkModel current;
  int activateCalls = 0;
  bool? lastReplace;
  int disableCalls = 0;

  @override
  Future<ShareLinkModel> status(String noteId) async => current;

  @override
  Future<ShareLinkModel> activate(String noteId, {bool replace = false}) async {
    activateCalls++;
    lastReplace = replace;
    current = const ShareLinkModel(
      active: true,
      url: 'https://notes.test/s/new',
    );
    return current;
  }

  @override
  Future<void> disable(String noteId) async {
    disableCalls++;
    current = const ShareLinkModel(active: false);
  }
}

Widget _harness(_FakeShareLinkRepository repository) {
  return ProviderScope(
    overrides: [
      shareLinkRepositoryProvider.overrideWithValue(repository),
      shareLinkStatusProvider.overrideWith(
        (ref, _) async => repository.current,
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: ShareLinkSection(noteId: 'note-1')),
    ),
  );
}

void main() {
  testWidgets('activates an inactive link without confirmation', (
    tester,
  ) async {
    final repository = _FakeShareLinkRepository(
      const ShareLinkModel(active: false),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ativar link público'));
    await tester.pumpAndSettle();

    expect(repository.activateCalls, 1);
    expect(repository.lastReplace, isFalse);
    expect(find.text('https://notes.test/s/new'), findsOneWidget);
  });

  testWidgets('requires confirmation before replacing an active link', (
    tester,
  ) async {
    final repository = _FakeShareLinkRepository(
      const ShareLinkModel(active: true, url: 'https://notes.test/s/old'),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Substituir'));
    await tester.pumpAndSettle();

    expect(find.text('Substituir link público?'), findsOneWidget);
    expect(repository.activateCalls, 0);

    await tester.tap(find.text('Substituir').last);
    await tester.pumpAndSettle();
    expect(repository.activateCalls, 1);
    expect(repository.lastReplace, isTrue);
  });

  testWidgets('requires confirmation before revoking an active link', (
    tester,
  ) async {
    final repository = _FakeShareLinkRepository(
      const ShareLinkModel(active: true, url: 'https://notes.test/s/old'),
    );
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revogar'));
    await tester.pumpAndSettle();

    expect(find.text('Revogar link público?'), findsOneWidget);
    expect(repository.disableCalls, 0);

    await tester.tap(find.text('Revogar').last);
    await tester.pumpAndSettle();
    expect(repository.disableCalls, 1);
  });
}
