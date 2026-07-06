library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/domain/settings_strings.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/features/settings/presentation/widgets/soul_footer.dart';
import 'package:supanotes/features/settings/presentation/widgets/soul_form.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

class SoulEditorScreen extends ConsumerStatefulWidget {
  const SoulEditorScreen({super.key});

  @override
  ConsumerState<SoulEditorScreen> createState() => _SoulEditorScreenState();
}

class _SoulEditorScreenState extends ConsumerState<SoulEditorScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      AppMessenger.showError(SettingsStrings.emptyError);
      return;
    }
    await ref.read(soulProvider.notifier).save(text);
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: SettingsStrings.restoreConfirmTitle,
      message: SettingsStrings.restoreConfirmMessage,
      confirmLabel: SettingsStrings.restoreConfirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _controller.text = SettingsStrings.defaultPersonality;
    AppMessenger.showInfo(SettingsStrings.restoredSnackbar);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SoulState>>(soulProvider, (prev, next) {
      next.whenOrNull(
        data: (state) {
          if (_controller.text.isEmpty) {
            _controller.text = state.soul.personality;
          }
          if (state.saveSuccess && prev?.value?.saveSuccess != true) {
            AppMessenger.showSuccess(SettingsStrings.savedSnackbar);
          }
          if (state.saveError != null &&
              prev?.value?.saveError != state.saveError) {
            final err = state.saveError;
            AppMessenger.showError(
              err is ApiException ? err.message : err.toString(),
            );
          }
        },
      );
    });

    final soulAsync = ref.watch(soulProvider);
    final isSaving = soulAsync.value?.isSaving ?? false;

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: SettingsStrings.title),
      body: Column(
        children: [
          Expanded(
            child: soulAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => AppErrorView(
                title: err is ApiException ? err.message : err.toString(),
                onRetry: () => ref.invalidate(soulProvider),
              ),
              data: (state) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SoulForm(controller: _controller),
              ),
            ),
          ),
          SoulFooter(
            isSaving: isSaving,
            onSave: _save,
            onRestore: _restoreDefault,
          ),
        ],
      ),
    );
  }
}
