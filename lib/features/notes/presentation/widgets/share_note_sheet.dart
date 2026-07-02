import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/note_strings.dart';
import '../../domain/share_permission.dart';
import '../controllers/share_list_controller.dart';
import '../controllers/share_note_controller.dart';
import 'share_list_section.dart';

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
//Essa logica aqui deveria ta no controller
  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _validationError = NoteStrings.shareErrorEmptyEmail);
      return;
    }

    setState(() => _validationError = null);

    await ref.read(shareNoteControllerProvider.notifier).share(
          noteId: widget.noteId,
          email: email,
          permission: _permission,
        );

    final state = ref.read(shareNoteControllerProvider);
    if (state.hasValue && mounted) {
      ref.invalidate(shareListProvider(widget.noteId));
      _emailCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareNoteControllerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          //Remover essas strings simples e passar direto aqui
          NoteStrings.shareDialogTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _emailCtrl,
          decoration: InputDecoration(
            labelText: NoteStrings.emailLabel,
            errorText: _validationError,
          ),
          enabled: !shareState.isLoading,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: AppSpacing.md),
        InputDecorator(
          decoration: InputDecoration(labelText: NoteStrings.permissionLabel),
          child: DropdownButton<SharePermission>(
            value: _permission,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                value: SharePermission.view,
                child: Text(NoteStrings.permissionView),
              ),
              DropdownMenuItem(
                value: SharePermission.edit,
                child: Text(NoteStrings.permissionEdit),
              ),
            ],
            onChanged: shareState.isLoading
                ? null
                : (val) => setState(() {
                      if (val != null) _permission = val;
                    }),
          ),
        ),
        ?shareState.whenOrNull(error: (err, _) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            err is ApiException ? err.message : err.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        )),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppButton(
                text: NoteStrings.closeLabel,
                variant: AppButtonVariant.secondary,
                onPressed:
                    shareState.isLoading ? null : () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                text: NoteStrings.addLabel,
                isLoading: shareState.isLoading,
                onPressed: shareState.isLoading ? null : _submit,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(height: 32),
        ShareListSection(noteId: widget.noteId),
      ],
    );
  }
}
