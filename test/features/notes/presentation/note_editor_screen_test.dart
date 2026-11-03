import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_provider.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_handle.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';

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
  Future<bool> reconcileRemote() async => true;

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
  setUpAll(() => initializeDateFormatting('pt_BR'));

  late NoteEditorController controller;
  late NoteEditorSession session;

  setUp(() {
    controller = NoteEditorController(
      userId: 'user-1',
      noteId: 'note-1',
      blocks: [
        NoteBlock(
          id: 'task-1',
          type: 'task',
          delta: const [
            {'insert': 'Target task'},
          ],
        ),
      ],
    );
    session = NoteEditorSession(
      noteId: 'note-1',
      controller: controller,
      syncSession: _ReadySyncHandle(),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, {String? blockId}) async {
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
          activeNotesProvider.overrideWith(
            (ref) => Stream.value([
              note,
              note.copyWith(id: 'note-2', title: 'Mercado'),
            ]),
          ),
          noteEditorSessionProvider(
            'note-1',
          ).overrideWith((ref) async => session),
          noteEditorCaptureProvider(
            'note-1',
          ).overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: NoteEditorScreen(noteId: 'note-1', blockId: blockId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the editor below the app bar with and without IME', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpScreen(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isFalse);

    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final editorTop = tester.getTopLeft(find.byType(AppFlowyEditor)).dy;
    expect(editorTop, greaterThanOrEqualTo(appBarBottom));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final keyboardAppBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final keyboardEditorTop = tester.getTopLeft(find.byType(AppFlowyEditor)).dy;
    expect(keyboardEditorTop, greaterThanOrEqualTo(keyboardAppBarBottom));
    // The editor ends above the keyboard instead of under it.
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final editorBottom = tester.getBottomLeft(find.byType(AppFlowyEditor)).dy;
    expect(
      editorBottom,
      lessThanOrEqualTo(
        screenHeight - 300 / tester.view.devicePixelRatio + 0.5,
      ),
    );
  });

  testWidgets('tapping below the text focuses the note and shows the toolbar', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byType(NoteToolbar), findsNothing);

    await _tapBelowText(tester);
    await tester.pumpAndSettle();

    final selection = controller.editorState.selection!;
    expect(selection.isCollapsed, isTrue);
    expect(selection.end.path, [0]);
    expect(selection.end.offset, 'Target task'.length);
    expect(find.byType(NoteToolbar), findsOneWidget);

    // Dismissing the keyboard keeps the note focusable again (the
    // "can't focus a new note" regression).
    await tester.tap(find.byTooltip('Remover foco'));
    await tester.pumpAndSettle();
    expect(controller.editorState.selection, isNull);
    expect(find.byType(NoteToolbar), findsNothing);

    await _tapBelowText(tester);
    await tester.pumpAndSettle();
    expect(controller.editorState.selection, isNotNull);
  });

  testWidgets('shows when the note was last edited above it', (
    tester,
  ) async {
    await pumpScreen(tester);

    // updatedAt is 2026-01-01T00:00Z, shown in local time (São Paulo).
    expect(find.text('31 de dezembro de 2025 às 21:00'), findsOneWidget);
    expect(find.text('Notas'), findsOneWidget);
  });

  testWidgets('selects an existing task block from the route state', (
    tester,
  ) async {
    await pumpScreen(tester, blockId: 'task-1');

    expect(controller.editorState.selection?.end.path, [0]);
  });

  testWidgets(
    'keeps a missing task target recoverable without hiding the note',
    (
      tester,
    ) async {
      await pumpScreen(tester, blockId: 'missing-task');

      expect(
        find.byKey(const ValueKey('missing-block:missing-task')),
        findsOneWidget,
      );
      expect(find.byType(AppFlowyEditor), findsOneWidget);
    },
  );

  testWidgets('Aa swaps the keyboard for the format panel and back', (
    tester,
  ) async {
    await pumpScreen(tester);
    await _tapBelowText(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Formatar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-format-panel')), findsOneWidget);
    expect(find.byType(NoteToolbar), findsNothing);

    await tester.tap(find.bySemanticsLabel('Título'));
    await tester.pumpAndSettle();
    expect(
      controller.editorState.getNodeAtPath([0])!.type,
      HeadingBlockKeys.type,
    );

    await tester.tap(find.bySemanticsLabel('Fechar formatação'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-format-panel')), findsNothing);
    expect(find.byType(NoteToolbar), findsOneWidget);
    // Still editing: the caret stays.
    expect(controller.editorState.selection, isNotNull);
  });

  testWidgets('the note scrolls behind the floating toolbar', (tester) async {
    await pumpScreen(tester);
    await _tapBelowText(tester);
    await tester.pumpAndSettle();

    final toolbarTop = tester.getTopLeft(find.byType(NoteToolbar)).dy;
    final editorBottom = tester.getBottomLeft(find.byType(AppFlowyEditor)).dy;
    expect(editorBottom, greaterThan(toolbarTop));
  });

  testWidgets('the keyboard going down does not close the format panel', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final dpr = tester.view.devicePixelRatio;
    await pumpScreen(tester);
    await _tapBelowText(tester);
    tester.view.viewInsets = FakeViewPadding(bottom: 320 * dpr);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Formatar'));
    await tester.pump();
    // The keyboard slides away one frame at a time.
    for (final inset in [280.0, 200.0, 120.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * dpr);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('note-format-panel'));
    expect(panel, findsOneWidget);
    // It takes the keyboard's full height, not a frame of its way down.
    expect(tester.getSize(panel).height, 320);

    // The keyboard coming back up replaces it.
    tester.view.viewInsets = FakeViewPadding(bottom: 150 * dpr);
    await tester.pump();
    expect(panel, findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('hiding the keyboard ends editing', (tester) async {
    await pumpScreen(tester);
    await _tapBelowText(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Esconder teclado'));
    await tester.pumpAndSettle();

    expect(controller.editorState.selection, isNull);
    expect(find.byType(NoteToolbar), findsNothing);
  });

  testWidgets('selected text links to a picked note', (tester) async {
    await pumpScreen(tester);
    controller.editorState.selection = Selection.single(
      path: [0],
      startOffset: 0,
      endOffset: 6,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Criar link para outra nota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mercado'));
    await tester.pumpAndSettle();

    final delta = controller.editorState.getNodeAtPath([0])!.delta!.toJson();
    expect(delta.first, {
      'insert': 'Target',
      'attributes': {'href': 'note://note-2'},
    });
  });

  testWidgets('a caret placed by code alone shows no toolbar', (tester) async {
    await pumpScreen(tester, blockId: 'task-1');

    // The deep link highlights the task without starting to edit.
    expect(controller.editorState.selection, isNotNull);
    expect(controller.editing.value, isFalse);
    expect(find.byType(NoteToolbar), findsNothing);
    expect(find.byTooltip('Remover foco'), findsNothing);

    await _tapBelowText(tester);
    await tester.pumpAndSettle();
    expect(controller.editing.value, isTrue);
    expect(find.byType(NoteToolbar), findsOneWidget);
  });
}

/// Taps the empty part of the note, below its last block.
Future<void> _tapBelowText(WidgetTester tester) async {
  final editor = tester.getRect(find.byType(AppFlowyEditor));
  await tester.tapAt(
    Offset(editor.center.dx, editor.top + editor.height * 0.6),
  );
  await tester.pumpAndSettle();
}
