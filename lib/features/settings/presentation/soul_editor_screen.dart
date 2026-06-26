library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/domain/settings_strings.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/features/settings/presentation/widgets/soul_footer.dart';
import 'package:supanotes/features/settings/presentation/widgets/soul_form.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class SoulEditorScreen extends ConsumerStatefulWidget {
  const SoulEditorScreen({super.key});

  @override
  ConsumerState<SoulEditorScreen> createState() => _SoulEditorScreenState();
}

class _SoulEditorScreenState extends ConsumerState<SoulEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _initialized = false;

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
    await ref.read(soulSaveProvider.notifier).save(text);
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
    ref.listen(soulSaveProvider, (prev, next) {
      if (prev == next || next.isLoading || !mounted) return;
      next.whenOrNull(
        data: (_) => AppMessenger.showSuccess(SettingsStrings.savedSnackbar),
        error: (err, _) => AppMessenger.showError(
          err is ApiException ? err.message : err.toString(),
        ),
      );
    });

    final soulAsync = ref.watch(soulProvider);
    final saveState = ref.watch(soulSaveProvider);
    final soul = soulAsync.asData?.value;

    if (!_initialized && soul != null) {
      _initialized = true;
      _controller.text = soul.personality;
    }

    return Scaffold(
      bottomNavigationBar: SoulFooter(
        isSaving: saveState.isLoading,
        onSave: _save,
        onRestore: _restoreDefault,
      ),
      body: CustomScrollView(
        slivers: [
          const AdaptiveSliverNavBar(title: Text(SettingsStrings.title)),
          soulAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              child: AppErrorView(
                title: err is ApiException ? err.message : err.toString(),
                onRetry: () => ref.invalidate(soulProvider),
              ),
            ),
            data: (_) => SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverFillRemaining(
                hasScrollBody: true,
                child: SoulForm(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
