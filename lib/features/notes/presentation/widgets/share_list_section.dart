import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../data/shares_repository.dart';
import '../../domain/note_strings.dart';
import '../../domain/share_model.dart';
import '../../domain/share_permission.dart';
import '../controllers/share_list_controller.dart';

class ShareListSection extends ConsumerWidget {
  const ShareListSection({super.key, required this.noteId});

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
      if (context.mounted) AppMessenger.showSuccess(NoteStrings.revokeSuccess);
    } catch (e) {
      if (context.mounted) {
        AppMessenger.showError(
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
        shareList.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text(
            error is ApiException ? error.message : error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          data: (value) => value.isEmpty
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
        ),
      ],
    );
  }
}

class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({required this.permission});

  final SharePermission permission;

  @override
  Widget build(BuildContext context) {
    final isEdit = permission == SharePermission.edit;
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
