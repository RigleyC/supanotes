import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/note_strings.dart';
import '../controllers/share_note_controller.dart';

class ShareNoteDialog extends ConsumerStatefulWidget {
  final String noteId;

  const ShareNoteDialog({super.key, required this.noteId});

  static Future<void> show(BuildContext context, String noteId) {
    return showDialog(
      context: context,
      builder: (_) => ShareNoteDialog(noteId: noteId),
    );
  }

  @override
  ConsumerState<ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends ConsumerState<ShareNoteDialog> {
  final _emailCtrl = TextEditingController();
  String _permission = 'view';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      AppMessenger.showError(context, NoteStrings.shareErrorEmptyEmail);
      return;
    }

    await ref.read(shareNoteControllerProvider.notifier).share(
          noteId: widget.noteId,
          email: email,
          permission: _permission,
        );

    final state = ref.read(shareNoteControllerProvider);
    if (state.hasValue && mounted) {
      Navigator.pop(context);
      AppMessenger.showSuccess(context, NoteStrings.shareSuccess);
    }
  }

  String? _errorMessage(AsyncValue<void> state) {
    if (!state.hasError) return null;
    final error = state.error;
    if (error is ApiException) return error.message;
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareNoteControllerProvider);
    final errorMessage = _errorMessage(shareState);

    return AlertDialog(
      title: Text(NoteStrings.shareDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _emailCtrl,
            decoration: InputDecoration(labelText: NoteStrings.emailLabel),
            enabled: !shareState.isLoading,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(labelText: NoteStrings.permissionLabel),
            child: DropdownButton<String>(
              value: _permission,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 'view',
                  child: Text(NoteStrings.permissionView),
                ),
                DropdownMenuItem(
                  value: 'edit',
                  child: Text(NoteStrings.permissionEdit),
                ),
              ],
              onChanged: shareState.isLoading
                  ? null
                  : (val) => setState(() => _permission = val!),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ],
      ),
      actions: [
        IntrinsicWidth(
          child: AppButton(
            text: NoteStrings.closeLabel,
            variant: AppButtonVariant.secondary,
            onPressed: shareState.isLoading ? null : () => Navigator.pop(context),
          ),
        ),
        IntrinsicWidth(
          child: AppButton(
            text: NoteStrings.addLabel,
            isLoading: shareState.isLoading,
            onPressed: shareState.isLoading ? null : _submit,
          ),
        ),
      ],
    );
  }
}
