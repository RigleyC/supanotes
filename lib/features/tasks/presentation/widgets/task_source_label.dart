import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';

class TaskSourceLabel extends StatelessWidget {
  const TaskSourceLabel({required this.item, super.key});

  final TaskListItem item;

  @override
  Widget build(BuildContext context) {
    final source = item.isNote
        ? 'Nota${item.note?.noteTitle == null ? '' : ': ${item.note!.noteTitle}'}'
        : 'Task independente';
    return Text(
      source,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
