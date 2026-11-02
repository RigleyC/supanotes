import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/utils/recurrence.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/note_lifecycle_policy.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task_completion_record.dart';
import 'package:supanotes/features/tasks/domain/note_task_list_reader.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/domain/task_occurrence.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// A clock boundary used by task list providers and easily replaced in tests.
class TaskListClock {
  const TaskListClock([this._read, this._timerFactory]);

  final DateTime Function()? _read;
  final Timer Function(Duration, void Function())? _timerFactory;

  DateTime now() => _read?.call() ?? DateTime.now();

  Timer schedule(Duration delay, void Function() callback) =>
      _timerFactory?.call(delay, callback) ?? Timer(delay, callback);
}

final taskListClockProvider = Provider<TaskListClock>(
  (ref) => const TaskListClock(),
);

/// An effective, visible note document ready for task extraction.
class VisibleNoteDocument {
  const VisibleNoteDocument({
    required this.noteId,
    required this.noteTitle,
    required this.documentJson,
    this.createdAt,
  });

  factory VisibleNoteDocument.fromRows({
    required NoteQueryResult note,
    required LocalNoteDocumentData document,
  }) {
    final json = document.materializedDocumentJson;
    if (json == null) {
      throw StateError(
        'Visible note ${note.note.id} has no effective document',
      );
    }
    return VisibleNoteDocument(
      noteId: note.note.id,
      noteTitle: note.title,
      documentJson: json,
      createdAt: note.note.createdAt,
    );
  }

  final String noteId;
  final String noteTitle;
  final String documentJson;
  final DateTime? createdAt;
}

/// Visible notes are selected from the active catalog and joined with the
/// materialized effective-document stream. This keeps deleted, archived,
/// revoked and not-yet-hydrated notes out of the aggregation.
final StreamProvider<List<VisibleNoteDocument>> taskNotesVisibilityProvider =
    StreamProvider.autoDispose<List<VisibleNoteDocument>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || userId.isEmpty) {
        throw StateError('taskNotesVisibilityProvider requires an owner');
      }

      return _watchVisibleNoteDocuments(
        database: ref.watch(appDatabaseProvider),
        userId: userId,
      );
    });

Stream<List<VisibleNoteDocument>> _watchVisibleNoteDocuments({
  required AppDatabase database,
  required String userId,
}) {
  final notes = database.notesDao.watchAllActiveNotes(userId);
  final documents = database.noteOperationsDao.watchMaterializedDocuments();
  return _combineLatest2(
    notes,
    documents,
    (catalog, localDocuments) {
      final byId = <String, LocalNoteDocumentData>{
        for (final document in localDocuments) document.noteId: document,
      };
      final visible = <VisibleNoteDocument>[];
      for (final note in catalog) {
        // The DAO scopes rows to this account's ownership or membership. Keep
        // this defense-in-depth check so a stale/alternate catalog stream
        // cannot turn arbitrary permission metadata into task visibility.
        final isAuthorizedPermission =
            note.note.permission == 'view' || note.note.permission == 'edit';
        if (note.note.userId != userId && !isAuthorizedPermission) {
          continue;
        }
        if (note.note.deletedAt != null ||
            note.note.lifecycleState == emptyDraftLifecycleState ||
            (note.note.permission != null &&
                note.note.permission != 'view' &&
                note.note.permission != 'edit')) {
          continue;
        }
        final document = byId[note.note.id];
        if (document?.materializedDocumentJson == null) continue;
        visible.add(
          VisibleNoteDocument.fromRows(note: note, document: document!),
        );
      }
      return visible;
    },
  );
}

final _taskListProviderFamily = StreamProvider.autoDispose
    .family<List<TaskListItem>, bool>(
      (ref, includeNoteTasks) {
        final userId = ref.watch(currentUserIdProvider);
        if (userId == null || userId.isEmpty) {
          throw StateError('taskListProvider requires an authenticated user');
        }
        final database = ref.watch(appDatabaseProvider);
        final clock = ref.watch(taskListClockProvider);
        final standalone = database.tasksDao.watchTasks(userId);
        if (!includeNoteTasks) {
          return _watchOpenTasks(
            standalone: standalone,
            notes: null,
            clock: clock,
          );
        }
        return _watchOpenTasks(
          standalone: standalone,
          notes: _watchVisibleNoteDocuments(
            database: database,
            userId: userId,
          ),
          clock: clock,
        );
      },
    );

/// Watches the open task list, optionally including tasks extracted from
/// visible note documents.
final taskListProvider = ({required bool includeNoteTasks}) =>
    _taskListProviderFamily(includeNoteTasks);

final _completedTaskHistoryProviderFamily = StreamProvider.autoDispose
    .family<List<TaskHistoryEntry>, bool>(
      (ref, includeNoteTasks) {
        final userId = ref.watch(currentUserIdProvider);
        if (userId == null || userId.isEmpty) {
          throw StateError(
            'completedTaskHistoryProvider requires an authenticated user',
          );
        }
        final standalone = ref
            .watch(appDatabaseProvider)
            .tasksDao
            .watchTasks(userId);
        if (!includeNoteTasks) {
          return standalone.map(
            (rows) => buildCompletedTaskHistory(
              standalone: rows.map(TaskRepository.fromData),
              notes: const [],
              includeNoteTasks: false,
            ),
          );
        }
        return _combineLatest2(
          standalone,
          _watchVisibleNoteDocuments(
            database: ref.watch(appDatabaseProvider),
            userId: userId,
          ),
          (rows, notes) => buildCompletedTaskHistory(
            standalone: rows.map(TaskRepository.fromData),
            notes: notes,
            includeNoteTasks: true,
          ),
        );
      },
    );

/// Watches completion history, optionally including note-task completions.
final completedTaskHistoryProvider = ({required bool includeNoteTasks}) =>
    _completedTaskHistoryProviderFamily(includeNoteTasks);

/// Pure list projection used by the provider and result-focused tests.
List<TaskListItem> buildTaskList({
  required Iterable<Task> standalone,
  required Iterable<VisibleNoteDocument> notes,
  required bool includeNoteTasks,
  required DateTime now,
}) {
  final policy = TaskOccurrencePolicy(clock: () => now);
  final result = <TaskListItem>[];
  for (final task in standalone) {
    if (task.deletedAt != null) continue;
    final occurrence = policy.resolveCurrent(
      taskId: task.id,
      anchor: task.dueDate,
      recurrence: TaskRecurrence.parse(task.recurrenceRule),
      hasTime: task.hasTime,
      completedAtByScheduledAt: _taskCompletions(task),
    );
    final completed = task.recurrenceRule == null
        ? task.isCompleted || occurrence?.isCompleted == true
        : occurrence?.isCompleted == true;
    result.add(
      TaskListItem.task(
        task,
        scheduledAt: occurrence?.scheduledAt,
        isCompleted: completed,
        completedAt: task.recurrenceRule == null
            ? task.lastCompletedAt ?? occurrence?.completedAt
            : occurrence?.completedAt,
      ),
    );
  }

  if (includeNoteTasks) {
    final clockReader = NoteTaskListReader(clock: () => now);
    for (final visibleNote in notes) {
      final noteTasks = clockReader.read(
        noteId: visibleNote.noteId,
        noteTitle: visibleNote.noteTitle,
        documentJson: visibleNote.documentJson,
        createdAt: visibleNote.createdAt,
      );
      for (final task in noteTasks) {
        final isCompleted = task.isCompleted;
        result.add(
          TaskListItem.note(
            task,
            scheduledAt: task.dueDate,
            isCompleted: isCompleted,
            completedAt: task.completedAt,
          ),
        );
      }
    }
  }

  return _sortTaskListItems(result, now);
}

/// Pure history projection. The list is sorted by the real completion instant.
List<TaskHistoryEntry> buildCompletedTaskHistory({
  required Iterable<Task> standalone,
  required Iterable<VisibleNoteDocument> notes,
  required bool includeNoteTasks,
}) {
  final result = <TaskHistoryEntry>[];
  for (final task in standalone) {
    if (task.deletedAt != null) continue;
    final seen = <String>{};
    for (final archived in task.completionHistory) {
      final identity = _completionIdentity(
        archived.scheduledAt,
        archived.hasTime,
        archived.completedAt,
      );
      if (!seen.add(identity)) continue;
      result.add(
        TaskHistoryEntry(
          task: TaskListItem.task(
            task,
            scheduledAt: archived.scheduledAt,
            explicitScheduledAt: true,
            scheduledHasTime: archived.hasTime,
          ),
          scheduledAt: archived.scheduledAt ?? archived.completedAt,
          completedAt: archived.completedAt,
        ),
      );
    }
    if (task.recurrenceRule != null) {
      for (final entry in task.completions.entries) {
        final scheduledAt = DateTime.tryParse(entry.key);
        final completedAt = DateTime.tryParse(entry.value);
        if (scheduledAt == null || completedAt == null) continue;
        if (!seen.add(
          _completionIdentity(scheduledAt, task.hasTime, completedAt),
        )) {
          continue;
        }
        result.add(
          TaskHistoryEntry(
            task: TaskListItem.task(
              task,
              scheduledAt: scheduledAt,
              explicitScheduledAt: true,
            ),
            scheduledAt: scheduledAt,
            completedAt: completedAt,
          ),
        );
      }
    } else if (task.lastCompletedAt != null) {
      final identity = _completionIdentity(
        task.dueDate,
        task.hasTime,
        task.lastCompletedAt!,
      );
      if (!seen.add(identity)) continue;
      result.add(
        TaskHistoryEntry(
          task: TaskListItem.task(
            task,
            scheduledAt: task.dueDate,
            explicitScheduledAt: true,
          ),
          scheduledAt: task.dueDate ?? task.lastCompletedAt!,
          completedAt: task.lastCompletedAt!,
        ),
      );
    }
  }

  if (includeNoteTasks) {
    const reader = NoteTaskListReader();
    for (final visibleNote in notes) {
      for (final note in reader.readForHistory(
        noteId: visibleNote.noteId,
        noteTitle: visibleNote.noteTitle,
        documentJson: visibleNote.documentJson,
        createdAt: visibleNote.createdAt,
      )) {
        final completions = [...note.completionHistory];
        if (note.isRecurring) {
          completions.addAll(
            note.completions.entries.map(
              (entry) => TaskCompletionRecord(
                scheduledAt: entry.key,
                hasTime: note.hasTime,
                completedAt: entry.value,
              ),
            ),
          );
        } else if (note.lastCompletedAt != null) {
          completions.add(
            TaskCompletionRecord(
              scheduledAt: note.dueDate,
              hasTime: note.hasTime,
              completedAt: note.lastCompletedAt!,
            ),
          );
        }

        final seen = <String>{};
        for (final completion in completions) {
          final identity = _completionIdentity(
            completion.scheduledAt,
            completion.hasTime,
            completion.completedAt,
          );
          if (!seen.add(identity)) continue;
          result.add(
            TaskHistoryEntry(
              task: TaskListItem.note(
                note,
                scheduledAt: completion.scheduledAt,
                explicitScheduledAt: true,
                scheduledHasTime: completion.hasTime,
              ),
              scheduledAt: completion.scheduledAt ?? completion.completedAt,
              completedAt: completion.completedAt,
              note: note,
            ),
          );
        }
      }
    }
  }

  result.sort((left, right) {
    final completed = right.completedAt.compareTo(left.completedAt);
    if (completed != 0) return completed;
    return left.uiKey.compareTo(right.uiKey);
  });
  return result;
}

String _completionIdentity(
  DateTime? scheduledAt,
  bool hasTime,
  DateTime completedAt,
) =>
    '${scheduledAt == null ? 'null' : scheduledAtKey(scheduledAt, hasTime: hasTime)}|$hasTime|${completedAt.toUtc().toIso8601String()}';

Stream<List<TaskListItem>> _watchOpenTasks({
  required Stream<List<TaskData>> standalone,
  required Stream<List<VisibleNoteDocument>>? notes,
  required TaskListClock clock,
}) {
  final standaloneTasks = standalone.map(
    (rows) => rows.map(TaskRepository.fromData).toList(growable: false),
  );
  if (notes == null) {
    return _watchWithTemporalInvalidation(
      sources: _combineLatest2(
        standaloneTasks,
        Stream.value(const <VisibleNoteDocument>[]),
        (tasks, visibleNotes) => (tasks: tasks, notes: visibleNotes),
      ),
      clock: clock,
    );
  }
  return _watchWithTemporalInvalidation(
    sources: _combineLatest2(
      standaloneTasks,
      notes,
      (tasks, visibleNotes) => (tasks: tasks, notes: visibleNotes),
    ),
    clock: clock,
  );
}

Stream<List<TaskListItem>> _watchWithTemporalInvalidation({
  required Stream<({List<Task> tasks, List<VisibleNoteDocument> notes})>
  sources,
  required TaskListClock clock,
}) {
  final controller = StreamController<List<TaskListItem>>();
  Timer? timer;
  ({List<Task> tasks, List<VisibleNoteDocument> notes})? latest;

  void emit() {
    try {
      final snapshot = latest;
      if (snapshot == null) return;
      final now = clock.now();
      final items = buildTaskList(
        standalone: snapshot.tasks,
        notes: snapshot.notes,
        includeNoteTasks: snapshot.notes.isNotEmpty,
        now: now,
      );
      controller.add(items);
      timer?.cancel();
      final boundary = _nextTaskListBoundary(items, now);
      if (boundary == null) return;
      final delay = boundary.difference(now);
      timer = clock.schedule(
        delay.isNegative || delay == Duration.zero
            ? const Duration(milliseconds: 1)
            : delay,
        emit,
      );
    } on Object catch (error, stackTrace) {
      timer?.cancel();
      controller.addError(error, stackTrace);
    }
  }

  // One autosave re-runs both the catalog and the document queries, so the
  // combined source fires twice for the same change. Rebuilding the list on
  // the next event-loop turn coalesces those into a single rebuild.
  Timer? pendingEmit;
  final subscription = sources.listen(
    (snapshot) {
      latest = snapshot;
      pendingEmit ??= Timer(Duration.zero, () {
        pendingEmit = null;
        emit();
      });
    },
    onError: controller.addError,
    onDone: () {
      final hadPendingEmit = pendingEmit != null;
      pendingEmit?.cancel();
      pendingEmit = null;
      if (hadPendingEmit) emit();
      timer?.cancel();
      unawaited(controller.close());
    },
  );
  controller.onCancel = () async {
    timer?.cancel();
    pendingEmit?.cancel();
    await subscription.cancel();
  };
  return controller.stream;
}

DateTime? _nextTaskListBoundary(Iterable<TaskListItem> items, DateTime now) {
  var next = DateTime(now.year, now.month, now.day + 1);
  for (final item in items) {
    final boundary = item.dueDate;
    if (boundary == null) continue;
    final recurrence = TaskRecurrence.parse(
      item.isStandalone ? item.task?.recurrenceRule : item.note?.recurrenceRule,
    );
    final anchor = item.isStandalone ? item.task?.dueDate : item.note?.dueDate;
    final nextOccurrence = boundary.isAfter(now)
        ? boundary
        : recurrence == null
        ? null
        : nextDueDate(
            from: boundary,
            recurrence: recurrence,
            anchorDay: anchor?.day ?? boundary.day,
          );
    if (nextOccurrence != null &&
        nextOccurrence.isAfter(now) &&
        nextOccurrence.isBefore(next)) {
      next = nextOccurrence;
    }
  }
  return next;
}

/// Sorts open tasks: overdue, today, upcoming, undated; then by canonical
/// schedule, creation time and a stable UI key.
///
/// Sort keys are computed once per item. Building local [DateTime] values
/// queries the platform time zone, and the previous comparator rebuilt up to
/// ten of them per comparison (hundreds of thousands per sort for a large
/// library), which made every task-list refresh take hundreds of milliseconds.
List<TaskListItem> _sortTaskListItems(List<TaskListItem> items, DateTime now) {
  final context = _TaskSortContext(now);
  final keyed = [for (final item in items) _TaskSortKey.of(item, context)]
    ..sort(_compareTaskSortKeys);
  return [for (final key in keyed) key.item];
}

final class _TaskSortContext {
  _TaskSortContext(DateTime now)
    : nowWithTime = canonicalScheduledAt(now, hasTime: true),
      nowDateOnly = canonicalScheduledAt(now, hasTime: false),
      today = DateTime(now.year, now.month, now.day);

  final DateTime nowWithTime;
  final DateTime nowDateOnly;
  final DateTime today;
}

final class _TaskSortKey {
  const _TaskSortKey({
    required this.item,
    required this.group,
    required this.canonicalDue,
    required this.createdAt,
    required this.uiKey,
  });

  factory _TaskSortKey.of(TaskListItem item, _TaskSortContext context) {
    final due = item.dueDate;
    final hasTime = item.hasTime;
    final canonicalDue = due == null
        ? null
        : canonicalScheduledAt(due, hasTime: hasTime);
    return _TaskSortKey(
      item: item,
      group: _taskGroup(due, canonicalDue, hasTime: hasTime, context: context),
      canonicalDue: canonicalDue,
      createdAt: item.createdAt,
      uiKey: item.uiKey,
    );
  }

  final TaskListItem item;
  final int group;
  final DateTime? canonicalDue;
  final DateTime? createdAt;
  final String uiKey;
}

int _compareTaskSortKeys(_TaskSortKey left, _TaskSortKey right) {
  if (left.group != right.group) return left.group - right.group;
  final leftDate = left.canonicalDue;
  final rightDate = right.canonicalDue;
  if (leftDate != null && rightDate != null) {
    final date = leftDate.compareTo(rightDate);
    if (date != 0) return date;
  } else if (leftDate != null) {
    return -1;
  } else if (rightDate != null) {
    return 1;
  }
  final leftCreated = left.createdAt;
  final rightCreated = right.createdAt;
  if (leftCreated != null && rightCreated != null) {
    final created = leftCreated.compareTo(rightCreated);
    if (created != 0) return created;
  }
  return left.uiKey.compareTo(right.uiKey);
}

int _taskGroup(
  DateTime? due,
  DateTime? canonicalDue, {
  required bool hasTime,
  required _TaskSortContext context,
}) {
  if (due == null || canonicalDue == null) return 3;
  final normalizedNow = hasTime ? context.nowWithTime : context.nowDateOnly;
  if (canonicalDue.isBefore(normalizedNow)) return 0;
  final dueDay = DateTime(due.year, due.month, due.day);
  if (dueDay == context.today) return 1;
  return 2;
}

Map<DateTime, DateTime> _taskCompletions(Task task) {
  final result = <DateTime, DateTime>{};
  for (final entry in task.completions.entries) {
    final scheduledAt = DateTime.tryParse(entry.key);
    if (scheduledAt != null) {
      result[scheduledAt] = DateTime.parse(entry.value);
    }
  }
  return result;
}

Stream<R> _combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A first, B second) combine,
) {
  final controller = StreamController<R>();
  A? firstValue;
  B? secondValue;
  var hasFirst = false;
  var hasSecond = false;
  void emit() {
    if (hasFirst && hasSecond) {
      try {
        controller.add(combine(firstValue as A, secondValue as B));
      } on Object catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }
  }

  late final StreamSubscription<A> firstSubscription;
  late final StreamSubscription<B> secondSubscription;
  firstSubscription = first.listen(
    (value) {
      firstValue = value;
      hasFirst = true;
      emit();
    },
    onError: controller.addError,
  );
  secondSubscription = second.listen(
    (value) {
      secondValue = value;
      hasSecond = true;
      emit();
    },
    onError: controller.addError,
  );
  controller.onCancel = () async {
    await firstSubscription.cancel();
    await secondSubscription.cancel();
  };
  return controller.stream;
}
