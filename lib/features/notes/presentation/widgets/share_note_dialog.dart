import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../data/shares_repository.dart';
import '../../domain/note_strings.dart';
import '../../domain/share_model.dart';
import '../controllers/share_note_controller.dart';
import '../controllers/share_list_controller.dart';


//Transformar isso aqui num modal
class ShareNoteDialog extends ConsumerStatefulWidget {
  final String noteId;

  const ShareNoteDialog({super.key, required this.noteId});

  //Isso aqui não existe, o certo é criar o widget e usar o showDialogGlobal passando ele.
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
      ref.invalidate(shareListProvider(widget.noteId));
      _emailCtrl.clear();
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
          const Divider(height: 32),
          _ShareListSection(noteId: widget.noteId),
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

class _ShareListSection extends ConsumerWidget {
  const _ShareListSection({required this.noteId});

  final String noteId;

  Future<void> _revoke(BuildContext context, WidgetRef ref, ShareModel share) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: NoteStrings.revokeConfirmTitle,
      message: NoteStrings.revokeConfirmMessage,
    );
    if (confirmed != true) return;

    try {
      await ref.read(sharesRepositoryProvider).deleteShare(
        noteId: noteId,
        userId: share.userId,
      );
      ref.invalidate(shareListProvider(noteId));
      if (context.mounted) AppMessenger.showSuccess(context, NoteStrings.revokeSuccess);
    } catch (e) {
      if (context.mounted) {
        AppMessenger.showError(
          context,
          e is ApiException ? e.message : e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shareList = ref.watch(shareListProvider(noteId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          NoteStrings.sharesTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        switch (shareList) {
          AsyncLoading() => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          AsyncError(:final error) => Text(
              error is ApiException ? error.message : error.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          AsyncData(:final value) => value.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    NoteStrings.noShares,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < value.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(value[i].email),
                        subtitle: value[i].name.isNotEmpty ? Text(value[i].name) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PermissionBadge(permission: value[i].permission),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              iconSize: 20,
                              onPressed: () => _revoke(context, ref, value[i]),
                              tooltip: NoteStrings.revokeLabel,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        },
      ],
    );
  }
}

class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({required this.permission});

  final String permission;

  @override
  Widget build(BuildContext context) {
    final isEdit = permission == 'edit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isEdit
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isEdit ? NoteStrings.permissionEdit : NoteStrings.permissionView,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
