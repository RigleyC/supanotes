import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_input.dart';

class TaskEditorForm extends StatelessWidget {
  const TaskEditorForm({
    required this.titleController,
    required this.draftNotifier,
    this.titleFocusNode,
    this.onSubmitted,
    this.errorText,
    super.key,
  });

  final TextEditingController titleController;
  final ValueNotifier<TaskMetadataDraft> draftNotifier;
  final FocusNode? titleFocusNode;
  final VoidCallback? onSubmitted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.lg,
      children: [
        AppInput(
          controller: titleController,
          focusNode: titleFocusNode,
          hintText: 'O que precisa ser feito?',
          errorText: errorText,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted?.call(),
        ),
        TaskMetadataSheetBody(
          draft: draftNotifier.value,
          draftNotifier: draftNotifier,
        ),
      ],
    );
  }
}
