import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

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
    final isIos26 = PlatformInfo.isIOS26OrHigher();
    return AdaptivePopupMenuButton.icon<String>(
      icon: isIos26 ? 'ellipsis' : Icons.more_horiz,
      items: [
        AdaptivePopupMenuItem<String>(
          label: includeNoteTasks
              ? 'Ocultar tarefas das notas'
              : 'Mostrar tarefas das notas',
          icon: isIos26
              ? (includeNoteTasks ? 'eye.slash' : 'note.text')
              : (includeNoteTasks
                    ? Icons.visibility_off_outlined
                    : Icons.notes_outlined),
          value: 'toggle-note-tasks',
        ),
      ],
      onSelected: (_, entry) {
        if (entry.value == 'toggle-note-tasks') {
          onChanged(!includeNoteTasks);
        }
      },
    );
  }
}
