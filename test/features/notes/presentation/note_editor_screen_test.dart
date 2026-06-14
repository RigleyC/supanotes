import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.controller);

  final StreamController<NoteModel?> controller;

  @override
  Stream<NoteModel?> watchNoteById(String id) => controller.stream;

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  }) async {}

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('initialized editor stays visible during stream refresh', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note-1')),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Persisted note',
        excerpt: null,
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Persisted note',
        excerpt: null,
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 12),
      ),
    );
    await tester.pump();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('dark mode editor uses primary color for mobile caret controls', (
    tester,
  ) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const NoteEditorScreen(noteId: 'note-1'),
        ),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        userId: 'u-1',
        title: 'Dark note',
        excerpt: null,
        content: 'Dark content',
        favorite: false,
        archived: false,
        isInbox: false,
        contextId: null,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
      ),
    );
    await tester.pumpAndSettle();

    final primary = AppTheme.darkTheme.colorScheme.primary;
    final androidScope = tester.widget<SuperEditorAndroidControlsScope>(
      find.byType(SuperEditorAndroidControlsScope).first,
    );
    final iosScope = tester.widget<SuperEditorIosControlsScope>(
      find.byType(SuperEditorIosControlsScope).first,
    );

    expect(androidScope.controller.controlsColor, primary);
    expect(iosScope.controller.handleColor, primary);
  });
}
