import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/sharing/data/share_link_repository.dart';
import 'package:supanotes/features/notes/sharing/domain/share_link_strings.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class ShareLinkSection extends ConsumerStatefulWidget {
  const ShareLinkSection({required this.noteId, super.key});

  final String noteId;

  @override
  ConsumerState<ShareLinkSection> createState() => _ShareLinkSectionState();
}

class _ShareLinkSectionState extends ConsumerState<ShareLinkSection> {
  AsyncValue<void> _action = const AsyncData(null);

  Future<void> _activate({bool replace = false}) async {
    if (replace) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: ShareLinkStrings.replaceConfirmTitle,
        message: ShareLinkStrings.replaceConfirmMessage,
        confirmLabel: ShareLinkStrings.replaceConfirmLabel,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    await _runAction(
      () => ref
          .read(shareLinkRepositoryProvider)
          .activate(widget.noteId, replace: replace),
    );
  }

  Future<void> _disable() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: ShareLinkStrings.revokeConfirmTitle,
      message: ShareLinkStrings.revokeConfirmMessage,
      confirmLabel: ShareLinkStrings.revokeConfirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    await _runAction(
      () => ref.read(shareLinkRepositoryProvider).disable(widget.noteId),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _action = const AsyncLoading());
    try {
      await action();
      ref.invalidate(shareLinkStatusProvider(widget.noteId));
      if (mounted) setState(() => _action = const AsyncData(null));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _action = AsyncError(error, stackTrace));
    }
  }

  Future<void> _copy(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) AppMessenger.showSuccess(ShareLinkStrings.copySuccess);
    } catch (_) {
      if (mounted) AppMessenger.showError(ShareLinkStrings.actionError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(shareLinkStatusProvider(widget.noteId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ShareLinkStrings.sectionTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        status.when(
          loading: () => const SizedBox(
            height: 96,
            width: double.infinity,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 180,
            width: double.infinity,
            child: AppErrorView(
              title: ShareLinkStrings.statusError,
              subtitle: error.toString(),
              onRetry: () =>
                  ref.invalidate(shareLinkStatusProvider(widget.noteId)),
            ),
          ),
          data: (link) {
            if (!link.active || link.url == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(ShareLinkStrings.inactiveDescription),
                  const SizedBox(height: 8),
                  AppButton(
                    text: ShareLinkStrings.activate,
                    isLoading: _action.isLoading,
                    onPressed: _action.isLoading ? null : _activate,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(link.url!),
                const SizedBox(height: 8),
                AppButton(
                  text: ShareLinkStrings.copy,
                  variant: AppButtonVariant.secondary,
                  onPressed: _action.isLoading ? null : () => _copy(link.url!),
                ),
                const SizedBox(height: 8),
                AppButton(
                  text: ShareLinkStrings.replace,
                  variant: AppButtonVariant.secondary,
                  isLoading: _action.isLoading,
                  onPressed: _action.isLoading
                      ? null
                      : () => _activate(replace: true),
                ),
                const SizedBox(height: 8),
                AppButton(
                  text: ShareLinkStrings.revoke,
                  variant: AppButtonVariant.danger,
                  isLoading: _action.isLoading,
                  onPressed: _action.isLoading ? null : _disable,
                ),
              ],
            );
          },
        ),
        if (_action.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              ShareLinkStrings.actionError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
