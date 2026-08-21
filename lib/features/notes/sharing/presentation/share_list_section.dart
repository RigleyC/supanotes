import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/sharing/application/share_list_controller.dart';
import 'package:supanotes/features/notes/sharing/application/share_note_controller.dart';
import 'package:supanotes/features/notes/sharing/model/share_model.dart';
import 'package:supanotes/features/notes/sharing/model/share_permission.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class ShareListSection extends ConsumerWidget {
  const ShareListSection({required this.noteId, super.key});

  final String noteId;

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    ShareModel share,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remover compartilhamento?',
      message: 'Esta pessoa não verá mais esta nota.',
    );
    if (!confirmed) return;

    await ref
        .read(shareNoteControllerProvider(noteId).notifier)
        .revoke(userId: share.userId);

    if (ref.read(shareNoteControllerProvider(noteId)).hasError) {
      if (context.mounted) {
        AppMessenger.showError('Erro ao remover compartilhamento');
      }
      return;
    }

    ref.invalidate(shareListProvider(noteId));
    if (context.mounted) AppMessenger.showSuccess('Compartilhamento removido');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shareList = ref.watch(shareListProvider(noteId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compartilhamentos',
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
            error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          data: (value) => value.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nenhum compartilhamento', style: TextStyle()),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final share = value[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(share.email),
                      subtitle: share.name.isNotEmpty ? Text(share.name) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PermissionBadge(permission: share.permission),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            iconSize: 20,
                            onPressed: () => _revoke(context, ref, share),
                            tooltip: 'Remover',
                          ),
                        ],
                      ),
                    );
                  },
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
        isEdit ? 'Editar' : 'Visualizar',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
