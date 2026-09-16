import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/features/notes/preferences/data/user_note_preferences_repository.dart';

void main() {
  test(
    'two fast toggles keep the newest value when the older write fails',
    () async {
      final notes = _FakeNotesRepository(_note());
      final preferences = _FakePreferencesRepository(notes);
      final harness = _controller(notes, preferences);
      addTearDown(harness.container.dispose);
      final controller = harness.controller;
      final firstWrite = Completer<void>();

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        await firstWrite.future;
        throw StateError('first failed');
      };

      final first = controller.setHideCompleted(
        current: notes.note,
        value: true,
      );
      await pumpEventQueue();

      expect(notes.note.hideCompleted, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.saving);

      final second = controller.setHideCompleted(
        current: notes.note,
        value: false,
      );
      await second;
      expect(notes.note.hideCompleted, isFalse);

      firstWrite.complete();
      await expectLater(
        first,
        throwsA(isA<NotePreferenceMutationException>()),
      );

      expect(notes.note.hideCompleted, isFalse);
      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'rollback changes only the failed field and preserves newer fields',
    () async {
      final notes = _FakeNotesRepository(
        _note(),
      );
      final preferences = _FakePreferencesRepository(notes);
      final harness = _controller(notes, preferences);
      addTearDown(harness.container.dispose);
      final controller = harness.controller;

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        throw StateError('hide failed');
      };

      await controller.setCollapseImages(current: notes.note, value: true);
      await expectLater(
        controller.setHideCompleted(current: notes.note, value: true),
        throwsA(isA<NotePreferenceMutationException>()),
      );

      expect(notes.note.hideCompleted, isFalse);
      expect(notes.note.collapseImages, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.error);
    },
  );

  test(
    'retry clears the old error and returns to idle after success',
    () async {
      final notes = _FakeNotesRepository(_note());
      final preferences = _FakePreferencesRepository(notes);
      final harness = _controller(notes, preferences);
      addTearDown(harness.container.dispose);
      final controller = harness.controller;

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        throw StateError('temporary failure');
      };

      await expectLater(
        controller.setHideCompleted(current: notes.note, value: true),
        throwsA(isA<NotePreferenceMutationException>()),
      );
      expect(controller.state.status, NotePreferenceMutationStatus.error);
      expect(notes.note.hideCompleted, isFalse);

      await controller.setHideCompleted(current: notes.note, value: true);

      expect(notes.note.hideCompleted, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'concurrent mutations where first fails and second succeeds end with idle status and no error',
    () async {
      final notes = _FakeNotesRepository(
        _note(),
      );
      final preferences = _FakePreferencesRepository(notes);
      final harness = _controller(notes, preferences);
      addTearDown(harness.container.dispose);
      final controller = harness.controller;
      final secondWrite = Completer<void>();

      preferences.nextHideCompletedWrite = (_) async {
        throw StateError('hide failed');
      };
      preferences.nextCollapseImagesWrite = (_) async {
        await secondWrite.future;
      };

      final op1 = controller.setHideCompleted(current: notes.note, value: true);
      final op2 = controller.setCollapseImages(
        current: notes.note,
        value: true,
      );

      await expectLater(op1, throwsA(isA<NotePreferenceMutationException>()));
      expect(controller.state.status, NotePreferenceMutationStatus.error);

      secondWrite.complete();
      await op2; // op2 succeeds after op1 failed

      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
    },
  );
}

({
  ProviderContainer container,
  NotePreferenceMutationController controller,
})
_controller(
  _FakeNotesRepository notes,
  _FakePreferencesRepository preferences,
) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('user-1'),
      notesRepositoryProvider.overrideWithValue(notes),
      userNotePreferencesRepositoryProvider.overrideWithValue(preferences),
    ],
  );
  final provider = notePreferenceMutationControllerProvider('note-1');
  container.listen(provider, (_, _) {});
  return (container: container, controller: container.read(provider.notifier));
}

NoteModel _note({bool hideCompleted = false, bool collapseImages = false}) {
  return NoteModel(
    id: 'note-1',
    userId: 'user-1',
    content: '',
    title: 'Note',
    favorite: false,
    archived: false,
    hideCompleted: hideCompleted,
    collapseImages: collapseImages,
    createdAt: DateTime.utc(2026, 7, 26),
    updatedAt: DateTime.utc(2026, 7, 26),
    hasRemoteCopy: true,
    isEmptyDraft: false,
  );
}

class _FakePreferencesRepository implements UserNotePreferencesRepository {
  _FakePreferencesRepository(this.notes);

  final _FakeNotesRepository notes;
  Future<void> Function(bool value)? nextHideCompletedWrite;
  Future<void> Function(bool value)? nextCollapseImagesWrite;

  @override
  Future<void> setHideCompleted(
    String userId,
    String noteId,
    bool hideCompleted,
  ) async {
    final write = nextHideCompletedWrite;
    nextHideCompletedWrite = null;
    if (write != null) {
      await write(hideCompleted);
      return;
    }
    notes.applyHideCompleted(hideCompleted);
  }

  @override
  Future<void> setCollapseImages(
    String userId,
    String noteId,
    bool collapseImages,
  ) async {
    final write = nextCollapseImagesWrite;
    nextCollapseImagesWrite = null;
    if (write != null) {
      await write(collapseImages);
      return;
    }
    notes.applyCollapseImages(collapseImages);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.note);

  NoteModel note;

  void applyHideCompleted(bool value) {
    note = note.copyWith(hideCompleted: value);
  }

  void applyCollapseImages(bool value) {
    note = note.copyWith(collapseImages: value);
  }

  @override
  Future<void> updateNote(
    String id, {
    String? content,
    bool? collapseImages,
  }) async {
    if (collapseImages != null) {
      note = note.copyWith(collapseImages: collapseImages);
    }
  }

  @override
  Future<NoteModel?> getNoteById(String id) async =>
      note.id == id ? note : null;

  @override
  Stream<List<NoteModel>> watchNotes({bool favoritesOnly = false}) {
    return Stream.value([note]);
  }

  @override
  Stream<NoteModel?> watchNoteById(String id) {
    return Stream.value(note.id == id ? note : null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
