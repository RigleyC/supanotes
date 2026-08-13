import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';

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

  Future<void> pumpEditor(
    WidgetTester tester, {
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Note')),
          body: MediaQuery(
            data: MediaQueryData(viewInsets: viewInsets),
            child: NoteEditor(
              noteId: 'note-1',
              session: session,
              delegate: const NoteEditorDelegate(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('does not duplicate the scaffold app bar in document padding', (
    tester,
  ) async {
    await pumpEditor(tester);

    final editor = tester.widget<SuperEditor>(find.byType(SuperEditor));

    expect(editor.stylesheet.documentPadding?.top, 0);
  });

  testWidgets('keeps the toolbar at the resized body bottom', (tester) async {
    await pumpEditor(tester, viewInsets: const EdgeInsets.only(bottom: 300));

    final toolbar = find.byType(NoteToolbar);
    final toolbarBottom = tester.getBottomRight(toolbar).dy;

    expect(toolbarBottom, greaterThan(500));
  });
}
