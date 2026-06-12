import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.controller);

  final StreamController<NoteModel?> controller;

  @override
  Stream<NoteModel?> watchNoteById(String id) => controller.stream;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('initialized editor stays visible during stream refresh', (tester) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
        ],
        child: const MaterialApp(
          home: NoteEditorScreen(noteId: 'note-1'),
        ),
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
}
