import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_card.dart';
import 'package:supanotes/shared/widgets/app_input.dart';

class TaskEditorForm extends StatelessWidget {
  const TaskEditorForm({
    required this.titleController,
    required this.metadata,
    required this.onMetadataChanged,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
    this.isSaving = false,
    this.errorText,
    super.key,
  });

  final TextEditingController titleController;
  final TaskMetadataDraft metadata;
  final ValueChanged<TaskMetadataDraft> onMetadataChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final bool isSaving;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.md,
          children: [
            AppInput(
              controller: titleController,
              hintText: 'O que precisa ser feito?',
              errorText: errorText,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSave(),
            ),
            TaskMetadataSheetBody(
              draft: metadata,
              onChanged: onMetadataChanged,
            ),
            Row(
              spacing: AppSpacing.sm,
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Cancelar',
                    variant: AppButtonVariant.secondary,
                    onPressed: isSaving ? null : onCancel,
                  ),
                ),
                Expanded(
                  child: AppButton(
                    text: 'Salvar',
                    icon: const Icon(Icons.check_rounded),
                    isLoading: isSaving,
                    onPressed: isSaving ? null : onSave,
                  ),
                ),
              ],
            ),
            if (onDelete != null)
              AppButton(
                text: 'Excluir task',
                variant: AppButtonVariant.danger,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: isSaving ? null : onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
