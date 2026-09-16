import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_card.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';

class TaskForm extends StatelessWidget {
  const TaskForm({
    required this.titleController,
    required this.metadata,
    required this.onMetadataTap,
    required this.onSave,
    this.onDelete,
    this.isSaving = false,
    this.errorText,
    super.key,
  });

  final TextEditingController titleController;
  final TaskMetadataDraft metadata;
  final VoidCallback onMetadataTap;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final bool isSaving;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final recurrence = metadata.recurrence;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          AppInput(
            controller: titleController,
            labelText: 'Título',
            hintText: 'O que precisa ser feito?',
            errorText: errorText,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
          ),
          AppTile(
            contentPadding: EdgeInsets.zero,
            title: 'Data, horário e lembrete',
            subtitleWidget: TaskMetadataBadges(
              dueDate: metadata.scheduleAnchor,
              recurrence: recurrence,
              hasReminder: metadata.reminder != null,
              hasTime: metadata.hasTime,
              completions: metadata.completions,
            ),
            leading: const Icon(Icons.event_note_outlined),
            onTap: onMetadataTap,
          ),
          AppButton(
            text: 'Salvar',
            icon: const Icon(Icons.check_rounded),
            isLoading: isSaving,
            onPressed: isSaving ? null : onSave,
          ),
          if (onDelete != null) ...[
            AppButton(
              text: 'Excluir task',
              variant: AppButtonVariant.danger,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: isSaving ? null : onDelete,
            ),
          ],
        ],
      ),
    );
  }
}
