import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/daos/note_links_dao.dart';
import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'package:supanotes/core/database/daos/user_note_preferences_dao.dart';
import 'package:supanotes/features/notes/data/local/notes_local_repository.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

void main() {
  group('NotesRepository lifecycle', () {
    test('createLocalNote creates an empty local-only note by id', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      final note = await repo.createLocalNote(id: 'note-1');
      expect(note.id, 'note-1');
      expect(note.title, equals('Sem título'));
      expect(note.content, isEmpty);
    });

    test('deleteIfEmpty hard-deletes empty local-only notes', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.hardDeletedIds, contains('note-1'));
      expect(local.softDeletedIds, isEmpty);
    });

    test('deleteIfEmpty tombstones remote notes', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      await local.markHasRemoteCopy('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.softDeletedIds, contains('note-1'));
      expect(local.hardDeletedIds, isEmpty);
    });

    test('deleteIfEmpty does nothing for non-empty notes', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1', content: 'Hello');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      await repo.deleteIfEmptyOrTombstone('note-1');
      expect(local.hardDeletedIds, isEmpty);
      expect(local.softDeletedIds, isEmpty);
    });

    test('saveSnapshot writes content and tasks together', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      await repo.saveNoteSnapshot(
        id: 'note-1',
        content: 'B',
      );

      final saved = await local.getNoteById('note-1');
      expect(saved, isNotNull);
      expect(saved!.note.content, 'B');
    });

    test('saveSnapshot syncs note links from content', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('source-1');
      final tasksLocal = FakeTasksLocalRepository();
      final linksDao = FakeNoteLinksDao();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test(), linksDao);

      const content = 'Check out [Note A](note://a1b2c3d4-e5f6-7890-abcd-ef1234567890) '
          'and [Note B](note://b2c3d4e5-f6a7-8901-bcde-f12345678901)';

      await repo.saveNoteSnapshot(
        id: 'source-1',
        content: content,
      );

      final links = await linksDao.getLinksForNote('source-1');
      expect(links.length, 2);
      expect(links.any((l) => l.targetId == 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'), true);
      expect(links.any((l) => l.targetId == 'b2c3d4e5-f6a7-8901-bcde-f12345678901'), true);
    });

    test('saveSnapshot removes stale links and adds new ones', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('source-1');
      final tasksLocal = FakeTasksLocalRepository();
      final linksDao = FakeNoteLinksDao();

      await linksDao.createLink(
        sourceId: 'source-1',
        targetId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test(), linksDao);

      const content = 'Only [New Note](note://bbbbbbbb-cccc-dddd-eeee-ffffffffffff)';

      await repo.saveNoteSnapshot(
        id: 'source-1',
        content: content,
      );

      final links = await linksDao.getLinksForNote('source-1');
      expect(links.length, 1);
      expect(links.single.targetId, 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff');
    });

    test('saveSnapshot does nothing when NoteLinksDao is null', () async {
      final prefsDao = FakeUserNotePreferencesDao();
      final local = FakeNotesLocalRepository();
      await local.createNoteWithId('note-1');
      final tasksLocal = FakeTasksLocalRepository();
      final repo = NotesRepository(local, tasksLocal, prefsDao, AppDatabase.test());

      const content = '[Test](note://a1b2c3d4-e5f6-7890-abcd-ef1234567890)';

      // Should not throw when dao is null
      await repo.saveNoteSnapshot(
        id: 'note-1',
        content: content,
      );

      final saved = await local.getNoteById('note-1');
      expect(saved, isNotNull);
      expect(saved!.note.content, content);
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
  Stream<List<NoteQueryResult>> watchActiveNotes() => const Stream.empty();

  @override
  Stream<List<NoteQueryResult>> watchNotesByContext(String contextId) =>
      const Stream.empty();

  @override
  Stream<List<NoteQueryResult>> watchFavorites() => const Stream.empty();

  @override
  Stream<NoteQueryResult?> watchInbox() => const Stream.empty();

  @override
  Stream<NoteQueryResult?> watchNoteById(String id) => const Stream.empty();

  @override
  Stream<NoteWithTasksQueryResult?> watchNoteWithTasks(String id) => const Stream.empty();

  @override
  Future<NoteQueryResult?> getNoteById(String id) async {
    final data = _store[id];
    if (data == null) return null;
    return (note: data, favorite: false, archived: false, hideCompleted: false);
  }

  @override
  Future<NoteData> createNote() async =>
      throw UnimplementedError('not used in these tests');

  @override
  Future<NoteQueryResult> createNoteWithId(String id,
      {String content = ''}) async {
    final now = DateTime.now().toUtc();
    final data = NoteData(
      id: id,
      userId: userId,
      content: content,
      isInbox: false,
      createdAt: now,
      updatedAt: now,
      isDirty: false,
      hasRemoteCopy: false,
      collapseImages: false,
    );
    _store[id] = data;
    return (note: data, favorite: false, archived: false, hideCompleted: false);
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
  Future<NoteQueryResult> getOrCreateInboxNote() async =>
      throw UnimplementedError('not used in these tests');
}

class FakeTasksLocalRepository implements TasksLocalRepository {
  @override
  String get userId => 'test-user';

  @override
  Future<void> catchUpRecurringTasks() async {}

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
    double position = 0.0,
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
  Future<DateTime?> completeTask(String id) async => null;

  @override
  Future<void> reopenTask(String id) async {}

  @override
  Future<void> softDeleteTask(String id) async {}

  @override
  Future<void> deleteTask(String id) async {}

  @override
  Future<void> runInTransaction(Future<void> Function() action) async {
    await action();
  }
}

class FakeUserNotePreferencesDao implements UserNotePreferencesDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not implemented');
  @override
  Stream<UserNotePreferenceData?> watchPreference(
          String userId, String noteId) =>
      const Stream.empty();

  @override
  Future<UserNotePreferenceData?> getPreference(
          String userId, String noteId) =>
      Future.value(null);

  @override
  Future<List<UserNotePreferenceData>> getDirtyPreferences() =>
      Future.value([]);

  @override
  Future<void> clearDirtyFlag(String userId, String noteId) async {}

  @override
  Future<void> setFavorite(
      String userId, String noteId, bool favorite) async {}

  @override
  Future<void> setArchived(
      String userId, String noteId, bool archived) async {}

  @override
  Future<void> setHideCompleted(
      String userId, String noteId, bool hideCompleted) async {}

}

class FakeNoteLinksDao implements NoteLinksDao {
  final Map<String, NoteLinkData> _store = {};
  int _counter = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not implemented');

  @override
  Future<void> createLink({
    required String sourceId,
    required String targetId,
    String? relation,
  }) async {
    final id = 'link-${_counter++}';
    final now = DateTime.now().toUtc();
    _store[id] = NoteLinkData(
      id: id,
      sourceId: sourceId,
      targetId: targetId,
      relation: relation ?? 'related',
      createdAt: now,
      updatedAt: now,
      isDirty: true,
    );
  }

  @override
  Future<List<NoteLinkData>> getLinksForNote(String noteId) async {
    return _store.values
        .where((l) => l.sourceId == noteId || l.targetId == noteId)
        .toList();
  }

  @override
  Future<void> deleteLink(String id) async {
    _store.remove(id);
  }

  @override
  Stream<List<NoteLinkData>> watchLinksForNote(String noteId) =>
      const Stream.empty();

  @override
  Future<List<NoteLinkData>> getDirtyLinks() async => [];

  @override
  Future<void> clearDirtyFlag(String id, DateTime pushedUpdatedAt) async {}

  @override
  Future<void> upsertFromRemote(NoteLinkData link) async {}
}
