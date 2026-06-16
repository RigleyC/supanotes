import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/shares_repository.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_dialog.dart';

class _FakeSharesRepository implements SharesRepository {
  final List<({String noteId, String email, String permission})> shareCalls = [];

  Future<void> Function()? shareNoteFunc;

  @override
  Future<void> shareNote({
    required String noteId,
    required String email,
    required String permission,
  }) async {
    shareCalls.add((noteId: noteId, email: email, permission: permission));
    if (shareNoteFunc != null) await shareNoteFunc!();
  }
}

Widget _buildTestHarness({
  required SharesRepository repo,
  required String noteId,
}) {
  return ProviderScope(
    overrides: [
      sharesRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => ShareNoteDialog.show(ctx, noteId),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _FakeSharesRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeSharesRepository();
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(_buildTestHarness(repo: fakeRepo, noteId: 'note-1'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('displays email field and permission dropdown', (tester) async {
    await openDialog(tester);

    expect(find.text(NoteStrings.shareDialogTitle), findsOneWidget);
    expect(find.text(NoteStrings.emailLabel), findsOneWidget);
    expect(find.text(NoteStrings.permissionView), findsOneWidget);
    expect(find.text(NoteStrings.addLabel), findsOneWidget);
    expect(find.text(NoteStrings.closeLabel), findsOneWidget);
  });

  testWidgets('shows error when email is empty', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text(NoteStrings.addLabel));
    await tester.pumpAndSettle();

    expect(find.text(NoteStrings.shareErrorEmptyEmail), findsOneWidget);
  });

  testWidgets('calls shareNote with correct params', (tester) async {
    fakeRepo.shareNoteFunc = () async {};

    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(NoteStrings.addLabel));
    await tester.pumpAndSettle();

    expect(fakeRepo.shareCalls, hasLength(1));
    expect(fakeRepo.shareCalls[0].noteId, 'note-1');
    expect(fakeRepo.shareCalls[0].email, 'user@example.com');
    expect(fakeRepo.shareCalls[0].permission, 'view');
  });

  testWidgets('shows loading indicator during submission', (tester) async {
    final completer = Completer<void>();
    fakeRepo.shareNoteFunc = () => completer.future;

    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(NoteStrings.addLabel));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ShareNoteDialog), findsNothing);
  });

  testWidgets('closes dialog on success', (tester) async {
    fakeRepo.shareNoteFunc = () async {};

    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(NoteStrings.addLabel));
    await tester.pumpAndSettle();

    expect(find.byType(ShareNoteDialog), findsNothing);
  });

  testWidgets('shows error message on failure', (tester) async {
    fakeRepo.shareNoteFunc = () => throw Exception('API error');

    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'user@example.com');
    await tester.tap(find.text(NoteStrings.addLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('API error'), findsOneWidget);
  });
}
