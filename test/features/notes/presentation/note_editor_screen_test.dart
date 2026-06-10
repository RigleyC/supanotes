import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test_robots/flutter_test_robots.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_inspector.dart';
import 'package:super_editor/src/test/super_editor_test/supereditor_robot.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';

void main() {
  testWidgets('keeps final paragraph visible above the editor toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime(2026);
    final note = NoteModel(
      id: 'note-1',
      userId: 'user-1',
      title: 'Tasks',
      excerpt: null,
      content: '',
      isInbox: false,
      favorite: false,
      archived: false,
      contextId: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteProvider('note-1').overrideWith((ref) => Stream.value(note)),
          notesRepositoryProvider.overrideWithValue(_FakeNotesRepository(note)),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );
    await tester.pump();

    final document = SuperEditorInspector.findDocument()!;
    final composer =
        SuperEditorInspector.findComposer()! as MutableDocumentComposer;
    final firstNode = document.getNodeAt(0)!;

    tester
        .widget<SuperEditor>(find.byType(SuperEditor))
        .focusNode
        ?.requestFocus();
    composer.setSelectionWithReason(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: firstNode.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
      ),
      SelectionReason.userInteraction,
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Tarefa'));
    await tester.pump();
    expect(SuperEditorInspector.hasFocus(), isTrue);
    expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);

    await tester.typeImeText('task 1');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    await tester.typeImeText('task 2');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    await tester.typeImeText('task 3');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(SuperEditorInspector.hasFocus(), isTrue);
    expect(SuperEditorInspector.isImeConnectionOpen(), isTrue);
    final imeValue = imeClientGetter().currentTextEditingValue!;
    expect(imeValue.text, '. ');
    expect(imeValue.selection, const TextSelection.collapsed(offset: 2));
    expect(imeValue.composing, const TextRange(start: -1, end: -1));

    await tester.ime.sendDeltas(const [
      TextEditingDeltaNonTextUpdate(
        oldText: '. ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
      TextEditingDeltaNonTextUpdate(
        oldText: '. ',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
      TextEditingDeltaDeletion(
        oldText: '. ',
        deletedRange: TextRange(start: 1, end: 2),
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: -1, end: -1),
      ),
    ], getter: imeClientGetter);
    await tester.pump();

    await tester.ime.sendDeltas(const [
      TextEditingDeltaInsertion(
        oldText: '. ',
        textInserted: 'p',
        insertionOffset: 2,
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 2, end: 3),
      ),
    ], getter: imeClientGetter);
    await tester.pump();
    await tester.ime.sendDeltas(const [
      TextEditingDeltaReplacement(
        oldText: '. p',
        replacementText: 'pa',
        replacedRange: TextRange(start: 2, end: 3),
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 2, end: 4),
      ),
    ], getter: imeClientGetter);
    await tester.pump();
    await tester.ime.sendDeltas(const [
      TextEditingDeltaReplacement(
        oldText: '. pa',
        replacementText: 'par',
        replacedRange: TextRange(start: 2, end: 4),
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 2, end: 5),
      ),
    ], getter: imeClientGetter);
    await tester.pump();

    final lastNode = document.getNodeAt(document.nodeCount - 1);
    expect(lastNode, isA<ParagraphNode>());
    expect((lastNode as ParagraphNode).text.toPlainText(), 'par');

    final paragraphBottom = SuperEditorInspector.findComponentOffset(
      lastNode.id,
      Alignment.bottomLeft,
    ).dy;
    final toolbarTop = tester.getTopLeft(find.byType(NoteToolbar)).dy;

    expect(paragraphBottom, lessThan(toolbarTop));
  });
}

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.note);

  NoteModel note;

  @override
  Stream<List<NoteModel>> watchNotes({
    String? contextId,
    bool favoritesOnly = false,
  }) => Stream.value([note]);

  @override
  Stream<NoteModel?> watchInbox() => Stream.value(null);

  @override
  Stream<NoteModel?> watchNoteById(String id) => Stream.value(note);

  @override
  Future<NoteModel> upsertNote({
    required String id,
    String? title,
    String content = '',
    String? contextId,
  }) async {
    note = note.copyWith(id: id, title: title, content: content);
    return note;
  }

  @override
  Future<void> updateNote(
    String id, {
    String? title,
    String? content,
    bool? favorite,
    bool? archived,
    String? contextId,
  }) async {
    note = note.copyWith(
      title: title,
      content: content,
      favorite: favorite,
      archived: archived,
      contextId: contextId,
    );
  }

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<void> softDelete(String id) async {}

  @override
  Future<void> appendToInbox(String text) async {}

  @override
  Future<void> syncTasksFromDocument(
    String noteId,
    List<TaskEntry> tasks,
  ) async {}
}
