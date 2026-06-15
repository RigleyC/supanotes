import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/local/notes_local_repository.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  group('NotesRepository lifecycle', () {
    test('createLocalNote creates an empty local-only note by id', () async {
      final local = FakeNotesLocalRepository();
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal);

      final note = await repo.createLocalNote(id: 'note-1');
      expect(note.id, 'note-1');
      expect(note.title, isNull);
      expect(note.content, isEmpty);
    });

    test('deleteIfEmpty hard-deletes empty local-only notes', () async {
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal);

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.hardDeletedIds, contains('note-1'));
      expect(local.softDeletedIds, isEmpty);
    });

    test('deleteIfEmpty tombstones remote notes', () async {
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      await local.markHasRemoteCopy('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal);

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.softDeletedIds, contains('note-1'));
      expect(local.hardDeletedIds, isEmpty);
    });

    test('deleteIfEmpty does nothing for non-empty notes', () async {
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1', title: 'Hi', content: 'Hello');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal);

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.hardDeletedIds, isEmpty);
      expect(local.softDeletedIds, isEmpty);
    });

    test('saveSnapshot writes title content and tasks together', () async {
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal);

      await repo.saveNoteSnapshot(
        id: 'note-1',
        title: 'A',
        content: 'B',
        tasks: const [],
      );

      final saved = await local.getNoteById('note-1');
      expect(saved, isNotNull);
      expect(saved!.title, 'A');
      expect(saved.content, 'B');
    });
  });
}

class FakeNotesLocalRepository implements NotesLocalRepository {
  final Map<String, NoteData> _store = {};
  final List<String> hardDeletedIds = [];
  final List<String> softDeletedIds = [];

  @override
  String get userId => 'test-user';

  @override
  Stream<List<NoteData>> watchActiveNotes() => const Stream.empty();

  @override
  Stream<List<NoteData>> watchNotesByContext(String contextId) =>
      const Stream.empty();

  @override
  Stream<List<NoteData>> watchFavorites() => const Stream.empty();

  @override
  Stream<NoteData?> watchInbox() => const Stream.empty();

  @override
  Stream<NoteData?> watchNoteById(String id) => const Stream.empty();

  @override
  Future<NoteData?> getNoteById(String id) async => _store[id];

  @override
  Future<NoteData> createNote() async =>
      throw UnimplementedError('not used in these tests');

  @override
  Future<NoteData> createNoteWithId(String id,
      {String? title, String content = ''}) async {
    final now = DateTime.now().toUtc();
    final data = NoteData(
      id: id,
      userId: userId,
      title: title,
      content: content,
      isInbox: false,
      favorite: false,
      archived: false,
      createdAt: now,
      updatedAt: now,
      isDirty: false,
      hasRemoteCopy: false,
    );
    _store[id] = data;
    return data;
  }

  @override
  Future<void> createNoteRaw(NotesCompanion companion) async {}

  @override
  Future<void> upsertNoteRaw(NotesCompanion companion) async {}

  @override
  Future<void> updateNoteRaw(NotesCompanion companion) async {
    final id = companion.id.value;
    if (_store.containsKey(id)) {
      _store[id] = _store[id]!.copyWithCompanion(companion);
    }
  }

  @override
  Future<void> hardDeleteNote(String id) async {
    hardDeletedIds.add(id);
    _store.remove(id);
  }

  @override
  Future<void> markHasRemoteCopy(String id) async {
    if (_store.containsKey(id)) {
      _store[id] = _store[id]!.copyWith(hasRemoteCopy: true);
    }
  }

  @override
  Future<void> softDeleteNote(String id) async {
    softDeletedIds.add(id);
    if (_store.containsKey(id)) {
      _store[id] =
          _store[id]!.copyWith(deletedAt: Value(DateTime.now().toUtc()));
    }
  }

  @override
  Future<void> updateNoteContent(String id, String content) async {
    if (_store.containsKey(id)) {
      _store[id] = _store[id]!.copyWith(
        content: content,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }

  @override
  Future<NoteData> getOrCreateInboxNote() async =>
      throw UnimplementedError('not used in these tests');
}

class FakeTasksLocalRepository implements TasksLocalRepository {
  @override
  String get userId => 'test-user';

  @override
  Stream<List<TaskData>> watchTodayTasks() => const Stream.empty();

  @override
  Stream<List<TaskData>> watchOpenTasks({String? userId}) =>
      const Stream.empty();

  @override
  Stream<List<TaskData>> watchNoteTasks(String noteId) =>
      const Stream.empty();

  @override
  Future<List<TaskData>> getNoteTasks(String noteId) async => [];

  @override
  Future<void> createTask({
    required String id,
    required String noteId,
    required String title,
    String status = 'pending',
    int position = 0,
    TaskRecurrence? recurrence,
    DateTime? dueDate,
  }) async {}

  @override
  Future<void> reorderTasksBatch(List<String> orderedIds) async {}

  @override
  Future<void> updateTask(TasksCompanion companion) async {
    throw UnimplementedError('not used in these tests');
  }

  @override
  Future<void> completeTask(String id) async {}

  @override
  Future<void> reopenTask(String id) async {}

  @override
  Future<void> softDeleteTask(String id) async {}

  @override
  Future<void> deleteTask(String id) async {}
}
