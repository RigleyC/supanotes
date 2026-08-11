import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/sharing/application/share_list_controller.dart';
import 'package:supanotes/features/notes/sharing/application/share_note_controller.dart';
import 'package:supanotes/features/notes/sharing/model/share_permission.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'share_list_section.dart';
import 'share_link_section.dart';

class ShareNoteSheet extends ConsumerStatefulWidget {
  final String noteId;

  const ShareNoteSheet({super.key, required this.noteId});

  @override
  ConsumerState<ShareNoteSheet> createState() => _ShareNoteSheetState();
}

class _ShareNoteSheetState extends ConsumerState<ShareNoteSheet> {
  final _emailCtrl = TextEditingController();
  SharePermission _permission = SharePermission.view;
  String? _validationError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _validationError = 'Informe um e-mail');
      return;
    }

    setState(() => _validationError = null);

    await ref
        .read(shareNoteControllerProvider(widget.noteId).notifier)
        .share(email: email, permission: _permission);

    final succeeded = ref
        .read(shareNoteControllerProvider(widget.noteId))
        .when(data: (_) => true, loading: () => false, error: (_, _) => false);
    if (succeeded && mounted) {
      ref.invalidate(shareListProvider(widget.noteId));
      _emailCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareNoteControllerProvider(widget.noteId));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compartilhar Nota',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          AppInput(
            controller: _emailCtrl,
            labelText: 'E-mail',
            errorText: _validationError,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.md),
          _ShareSubmissionControls(
            state: shareState,
            permission: _permission,
            onPermissionChanged: (value) => setState(() => _permission = value),
            onSubmit: _submit,
          ),
          const SizedBox(height: AppSpacing.xxl),

          ShareListSection(noteId: widget.noteId),
          const SizedBox(height: AppSpacing.xxl),
          ShareLinkSection(noteId: widget.noteId),
        ],
      ),
    );
  }
}

class _ShareSubmissionControls extends StatelessWidget {
  const _ShareSubmissionControls({
    required this.state,
    required this.permission,
    required this.onPermissionChanged,
    required this.onSubmit,
  });

  final AsyncValue<void> state;
  final SharePermission permission;
  final ValueChanged<SharePermission> onPermissionChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => state.when(
    data: (_) => _ShareSubmissionFields(
      permission: permission,
      onPermissionChanged: onPermissionChanged,
      onSubmit: onSubmit,
    ),
    loading: () => _ShareSubmissionFields(
      permission: permission,
      onPermissionChanged: onPermissionChanged,
      onSubmit: onSubmit,
      isLoading: true,
    ),
    error: (error, _) => _ShareSubmissionFields(
      permission: permission,
      onPermissionChanged: onPermissionChanged,
      onSubmit: onSubmit,
      errorText: error.toString(),
    ),
  );
}

class _ShareSubmissionFields extends StatelessWidget {
  const _ShareSubmissionFields({
    required this.permission,
    required this.onPermissionChanged,
    required this.onSubmit,
    this.isLoading = false,
    this.errorText,
  });

  final SharePermission permission;
  final ValueChanged<SharePermission> onPermissionChanged;
  final VoidCallback onSubmit;
  final bool isLoading;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InputDecorator(
        decoration: const InputDecoration(),
        child: DropdownButton<SharePermission>(
          value: permission,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          isDense: true,
          items: const [
            DropdownMenuItem(
              value: SharePermission.view,
              child: Text('Visualizar'),
            ),
            DropdownMenuItem(
              value: SharePermission.edit,
              child: Text('Editar'),
            ),
          ],
          onChanged: isLoading
              ? null
              : (value) {
                  if (value != null) onPermissionChanged(value);
                },
        ),
      ),
      if (errorText != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.lg),
      AppButton(
        text: 'Adicionar',
        isLoading: isLoading,
        onPressed: isLoading ? null : onSubmit,
      ),
    ],
  );
}
