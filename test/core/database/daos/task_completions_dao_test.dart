import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  test('upsertCompletion is idempotent per task occurrence', () async {
    final db = AppDatabase.test();
    final scheduledAt = DateTime.utc(2026, 7, 20, 9);

    await db.taskCompletionsDao.upsertCompletion(
      taskId: 'task-1',
      userId: 'user-1',
      scheduledAt: scheduledAt,
      completedAt: DateTime.utc(2026, 7, 20, 10),
    );
    await db.taskCompletionsDao.upsertCompletion(
      taskId: 'task-1',
      userId: 'user-1',
      scheduledAt: scheduledAt,
      completedAt: DateTime.utc(2026, 7, 20, 11),
    );

    final completions = await db.select(db.localTaskCompletions).get();
    expect(completions, hasLength(1));
    expect(completions.single.taskId, 'task-1');

    await db.close();
  });
}
