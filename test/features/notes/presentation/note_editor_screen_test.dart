import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/core/auth/current_user.dart';

class _ReadySyncHandle implements NoteEditorSyncHandle {
  @override
  bool captureLocalOperations = true;

  @override
  Stream<bool> get captureLocalOperationsChanges => const Stream.empty();

  @override
  NoteSessionStatus status = NoteSessionStatus.ready;

  @override
  Stream<NoteSessionStatus> get statusChanges => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> flushNow() async {}

  @override
  Future<void> start() async {}

  @override
  void setCaptureLocalOperations(bool value) {
    captureLocalOperations = value;
  }
}

void main() {
  late NoteEditorController controller;
  late NoteEditorSession session;

  setUp(() {
    controller = NoteEditorController(userId: 'user-1', noteId: 'note-1');
    session = NoteEditorSession(
      noteId: 'note-1',
      controller: controller,
      syncSession: _ReadySyncHandle(),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final note = NoteModel(
      id: 'note-1',
      userId: 'user-1',
      content: '',
      title: 'Note',
      favorite: false,
      archived: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      hasRemoteCopy: true,
      isEmptyDraft: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          noteProvider('note-1').overrideWith((ref) => Stream.value(note)),
          noteEditorSessionProvider(
            'note-1',
          ).overrideWith((ref) async => session),
          noteEditorCaptureProvider(
            'note-1',
          ).overrideWith((ref) => Stream.value(true)),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the editor below the app bar with and without IME', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpScreen(tester);

    expect(find.byType(KeyboardScaffoldSafeArea), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    expect(scaffold.extendBodyBehindAppBar, isFalse);

    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final editorTop = tester.getTopLeft(find.byType(SuperEditor)).dy;
    expect(editorTop, greaterThanOrEqualTo(appBarBottom));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final keyboardAppBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final keyboardEditorTop = tester.getTopLeft(find.byType(SuperEditor)).dy;
    expect(keyboardEditorTop, greaterThanOrEqualTo(keyboardAppBarBottom));
  });
}
