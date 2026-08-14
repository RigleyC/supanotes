import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/application/note_editor_controller.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_delegate.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_session.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_formatting_panel.dart';
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
    List<DocumentNode>? nodes,
  }) async {
    if (nodes != null) {
      controller.dispose();
      controller = NoteEditorController(
        userId: 'user-1',
        noteId: 'note-1',
        nodes: nodes,
      );
      session = NoteEditorSession(
        noteId: 'note-1',
        controller: controller,
        syncSession: _ReadySyncHandle(),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardScaffoldSafeArea(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            appBar: AppBar(title: const Text('Note')),
            body: NoteEditor(
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

  testWidgets('shows the formatting panel and preserves the selection', (
    tester,
  ) async {
    const initialSelection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'paragraph-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );
    await pumpEditor(
      tester,
      nodes: [ParagraphNode(id: 'paragraph-1', text: AttributedText('Text'))],
    );
    controller.composer.setSelectionWithReason(initialSelection);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Abrir formatação'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteToolbar), findsOneWidget);
    expect(find.byType(NoteFormattingPanel), findsOneWidget);
    expect(controller.composer.selection, initialSelection);
  });

  testWidgets('closing formatting closes the IME until returning to typing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await pumpEditor(
      tester,
      nodes: [ParagraphNode(id: 'paragraph-1', text: AttributedText('Text'))],
    );
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'paragraph-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      ),
    );
    controller.focusNode.requestFocus();
    await tester.pumpAndSettle();

    const keyboardTop = 544.0;
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(
      tester.getBottomLeft(find.byType(NoteToolbar)).dy,
      lessThanOrEqualTo(keyboardTop),
    );

    await tester.tap(find.bySemanticsLabel('Abrir formatação'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteFormattingPanel), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(NoteFormattingPanel)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(NoteToolbar)).dy),
    );
    expect(
      tester.getBottomLeft(find.byType(NoteFormattingPanel)).dy,
      closeTo(844, 0.01),
    );

    await tester.tap(find.bySemanticsLabel('Fechar formatação'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteFormattingPanel), findsNothing);
    final hasImeConnectionAfterClose = tester.testTextInput.hasAnyClients;

    await tester.tap(find.bySemanticsLabel('Abrir formatação'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Voltar a digitar'));
    await tester.pumpAndSettle();

    expect(controller.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(hasImeConnectionAfterClose, isFalse);
  });

  testWidgets(
    'system back closes the formatting panel without leaving the note',
    (tester) async {
      await pumpEditor(
        tester,
        nodes: [ParagraphNode(id: 'paragraph-1', text: AttributedText('Text'))],
      );
      controller.composer.setSelectionWithReason(
        const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'paragraph-1',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );
      controller.focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Abrir formatação'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(NoteFormattingPanel), findsNothing);
      expect(find.byType(NoteEditor), findsOneWidget);
      final hasImeConnectionAfterSystemBack =
          tester.testTextInput.hasAnyClients;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(hasImeConnectionAfterSystemBack, isFalse);
    },
  );

  testWidgets('returns to typing with editor focus and an IME connection', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpEditor(
      tester,
      nodes: [ParagraphNode(id: 'paragraph-1', text: AttributedText('Text'))],
    );
    controller.composer.setSelectionWithReason(
      const DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: 'paragraph-1',
          nodePosition: TextNodePosition(offset: 0),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Abrir formatação'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteFormattingPanel), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Voltar a digitar'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(controller.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'keeps the caret above the toolbar while typing on ${platform.name}',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final nodes = List<DocumentNode>.generate(
          30,
          (index) => ParagraphNode(
            id: 'paragraph-$index',
            text: AttributedText('Paragraph $index'),
          ),
        );
        await pumpEditor(tester, nodes: nodes);

        final lastParagraph = nodes.last as ParagraphNode;
        controller.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: lastParagraph.id,
                nodePosition: lastParagraph.endPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
        controller.focusNode.requestFocus();
        await tester.pumpAndSettle();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();

        for (var index = 0; index < 8; index++) {
          await tester.testTextInput.receiveAction(TextInputAction.newline);
          await tester.pumpAndSettle();

          final caretBottom = tester
              .getBottomLeft(find.byKey(DocumentKeys.caret))
              .dy;
          final toolbarTop = tester.getTopLeft(find.byType(NoteToolbar)).dy;
          expect(caretBottom, lessThanOrEqualTo(toolbarTop));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
        tester.view.reset();
      },
    );
  }
}
