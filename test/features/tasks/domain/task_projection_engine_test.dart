import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/core/database/daos/tasks_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/projected_task.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';

class FailingTasksDao extends TasksDao {
  FailingTasksDao(super.db);

  @override
  Future<void> syncProjectedTasksForNoteTyped(
    String noteId,
    List<ProjectedTask> projectedTasks, {
    String userId = '',
  }) async {
    throw Exception('Simulated DB failure during task sync');
  }
}

class TestFailingDatabase extends AppDatabase {
  TestFailingDatabase() : super.test();

  @override
  TasksDao get tasksDao => FailingTasksDao(this);
}

void main() {
  late AppDatabase db;
  late TaskProjectionEngine engine;

  setUp(() {
    db = AppDatabase.test();
    engine = TaskProjectionEngine(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('projects content and tasks atomically from snapshot into SQLite', () async {
    const noteId = 'note-atomic-1';
    const userId = 'user-1';

    // Create base note in database
    await db.notesDao.createNote(
      NotesCompanion.insert(
        id: noteId,
        userId: userId,
        content: 'Old Content',
        excerpt: const Value('Old Content'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final snapshot = {
      'blocks': [
        {
          'id': 'block-1',
          'type': 'paragraph',
          'content': [
            {'insert': 'First paragraph'}
          ],
        },
        {
          'id': 'task-1',
          'type': 'task',
          'metadata': {'isCompleted': false},
          'content': [
            {'insert': 'Buy milk'}
          ],
        },
      ],
    };

    await engine.projectTasksFromSnapshot(
      noteId: noteId,
      snapshot: snapshot,
      userId: userId,
    );

    final note = await db.notesDao.getNoteById(noteId);
    expect(note, isNotNull);
    expect(note!.content, contains('First paragraph'));
    expect(note.excerpt, contains('First paragraph'));

    final tasks = await (db.select(db.tasks)..where((t) => t.noteId.equals(noteId))).get();
    expect(tasks, hasLength(1));
    expect(tasks.first.title, 'Buy milk');
  });

  test('clears content, sets excerpt to null, and deletes tasks when note becomes empty', () async {
    const noteId = 'note-empty-1';
    const userId = 'user-1';

    // Insert note with content and a task
    await db.notesDao.createNote(
      NotesCompanion.insert(
        id: noteId,
        userId: userId,
        content: 'Has content',
        excerpt: const Value('Has content'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await engine.projectTasksFromSnapshot(
      noteId: noteId,
      snapshot: {
        'blocks': [
          {
            'id': 'task-1',
            'type': 'task',
            'metadata': {'isCompleted': false},
            'content': [
              {'insert': 'Task to delete'}
            ],
          },
        ],
      },
      userId: userId,
    );

    // Verify initial state
    var note = await db.notesDao.getNoteById(noteId);
    expect(note!.content, 'Task to delete');
    expect(note.excerpt, 'Task to delete');

    // Project empty document
    final emptyDocument = MutableDocument(nodes: []);
    await engine.projectTasksFromDocument(
      noteId: noteId,
      document: emptyDocument,
      userId: userId,
    );

    // Verify note content is "" and excerpt is null
    note = await db.notesDao.getNoteById(noteId);
    expect(note!.content, '');
    expect(note.excerpt, isNull);

    // Verify tasks are soft-deleted
    final activeTasks = await (db.select(db.tasks)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull()))
        .get();
    expect(activeTasks, isEmpty);
  });

  test('rolls back note and task updates atomically when projection fails during TaskProjectionEngine execution', () async {
    const noteId = 'note-rollback-prod';
    const userId = 'user-1';

    final failingDb = TestFailingDatabase();
    final failingEngine = TaskProjectionEngine(database: failingDb);

    try {
      // 1. Insert original note state and task into failingDb
      await failingDb.notesDao.createNote(
        NotesCompanion.insert(
          id: noteId,
          userId: userId,
          content: 'Original Content',
          excerpt: const Value('Original Excerpt'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await failingDb.into(failingDb.tasks).insert(
        TasksCompanion.insert(
          id: 'original-task-1',
          noteId: noteId,
          userId: userId,
          title: 'Original Task',
          status: 'open',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 2. Call production TaskProjectionEngine.projectTasksFromSnapshot
      // notesDao.updateNoteProjection will execute inside saveProjectedDocument transaction,
      // then tasksDao.syncProjectedTasksForNoteTyped will throw Exception, causing transaction rollback.
      final newSnapshot = {
        'blocks': [
          {
            'id': 'block-1',
            'type': 'paragraph',
            'content': [
              {'insert': 'Modified Content'}
            ],
          },
          {
            'id': 'task-new',
            'type': 'task',
            'metadata': {'isCompleted': false},
            'content': [
              {'insert': 'New Task'}
            ],
          },
        ],
      };

      await expectLater(
        failingEngine.projectTasksFromSnapshot(
          noteId: noteId,
          snapshot: newSnapshot,
          userId: userId,
        ),
        throwsA(isA<Exception>()),
      );

      // 3. Verify atomic rollback in SQLite: notes.content, notes.excerpt, and tasks retain original values
      final note = await failingDb.notesDao.getNoteById(noteId);
      expect(note!.content, 'Original Content');
      expect(note.excerpt, 'Original Excerpt');

      final tasks = await (failingDb.select(failingDb.tasks)
            ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull()))
          .get();
      expect(tasks, hasLength(1));
      expect(tasks.first.title, 'Original Task');
    } finally {
      await failingDb.close();
    }
  });
}
