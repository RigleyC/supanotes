import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_date_filter.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

TaskModel _task({DateTime? dueDate, bool completed = false, DateTime? createdAt}) => TaskModel(
      id: '1',
      userId: 'u',
      noteId: 'n',
      title: 't',
      status: completed ? 'done' : 'open',
      position: '0',
      dueDate: dueDate,
      completedAt: completed ? DateTime.now() : null,
      recurrence: null,
      createdAt: createdAt ?? DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
    );

void main() {
  final today = DateTime(2026, 6, 15);

  test('filters overdue tasks', () {
    final tasks = [
      _task(dueDate: today.subtract(const Duration(days: 1))),
      _task(dueDate: today),
      _task(dueDate: today.add(const Duration(days: 1))),
    ];
    final result = TaskDateFilter.overdue(tasks, today: today);
    expect(result, hasLength(1));
    expect(result.single.dueDate!.day, 14);
  });

  test('filters today tasks', () {
    final tasks = [
      _task(dueDate: today),
      _task(dueDate: today.subtract(const Duration(days: 1))),
    ];
    final result = TaskDateFilter.today(tasks, today: today);
    expect(result, hasLength(1));
    expect(result.single.dueDate!.day, 15);
  });

  test('filters undated tasks', () {
    final tasks = [_task(), _task(dueDate: today)];
    final result = TaskDateFilter.undated(tasks);
    expect(result, hasLength(1));
    expect(result.single.dueDate, isNull);
  });
}
