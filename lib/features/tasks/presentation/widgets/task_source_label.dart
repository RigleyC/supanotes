import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';

class TaskSourceLabel extends StatelessWidget {
  const TaskSourceLabel({required this.item, super.key});

  final TaskListItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isStandalone) return const SizedBox.shrink();
    final source =
        'Nota${item.note?.noteTitle == null ? '' : ': ${item.note!.noteTitle}'}';
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
