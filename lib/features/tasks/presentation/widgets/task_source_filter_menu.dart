import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/app_popup_menu.dart';

/// Toggles whether note tasks are included in the global task feed.
///
/// The same adaptive menu is used by the open-task list and completion
/// history, keeping the filter discoverable without spending list space.
class TaskSourceFilterMenu extends StatelessWidget {
  const TaskSourceFilterMenu({
    required this.includeNoteTasks,
    required this.onChanged,
    super.key,
  });

  final bool includeNoteTasks;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = includeNoteTasks
        ? 'Ocultar tarefas das notas'
        : 'Mostrar tarefas das notas';
    return AppPopupMenu<String>(
      icon: Icons.more_horiz,
      onSelected: (_) => onChanged(!includeNoteTasks),
      items: [
        AppPopupMenuItem(label: label, value: 'toggle-note-tasks'),
      ],
    );
  }
}
