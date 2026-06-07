library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

class _SoulStrings {
  _SoulStrings._();

  static const String title = 'Personalidade do agent';
  static const String save = 'Salvar';
  static const String saving = 'Salvando…';
  static const String restore = 'Restaurar padrão';
  static const String restoreConfirmTitle = 'Restaurar personalidade padrão?';
  static const String restoreConfirmMessage =
      'O texto atual será substituído pelo padrão. Esta ação não pode ser desfeita.';
  static const String restoreConfirmLabel = 'Restaurar';

  static const String editMode = 'Editar';
  static const String previewMode = 'Visualizar';
  static const String previewTooltip = 'Alternar entre editar e visualizar';

  static const String hint =
      'Descreva como o agent deve se comportar (estilo, tom, escopo).';
  static const String previewEmpty =
      'Nada para visualizar. Volte ao modo Editar para escrever.';

  static const String savedSnackbar = 'Personalidade atualizada.';
  static const String restoredSnackbar = 'Texto restaurado.';
  static const String emptyError = 'A personalidade não pode ficar vazia.';
}

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
      AppMessenger.showError(context, _SoulStrings.emptyError);
      return;
    }
    try {
      await ref.read(soulEditorControllerProvider.notifier).save(text);
      if (!mounted) return;
      AppMessenger.showSuccess(context, _SoulStrings.savedSnackbar);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, e.message);
    }
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: _SoulStrings.restoreConfirmTitle,
      message: _SoulStrings.restoreConfirmMessage,
      confirmLabel: _SoulStrings.restoreConfirmLabel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    ref.read(soulEditorControllerProvider.notifier).restoreDefault();
    final restored =
        ref.read(soulEditorControllerProvider).asData?.value;
    if (restored?.soul != null) {
      _controller.text = restored!.soul!.personality;
    }
    AppMessenger.showInfo(context, _SoulStrings.restoredSnackbar);
  }

  @override
  Widget build(BuildContext context) {
    final soulAsync = ref.watch(soulEditorControllerProvider);
    final state = soulAsync.asData?.value;

    if (!_initialized && state?.soul != null) {
      _initialized = true;
      _controller.text = state!.soul!.personality;
    }

    final isEditing = state?.isEditing ?? true;
    final isSaving = state?.isSaving ?? false;
    final loadError = state?.loadError;

    return Scaffold(
      appBar: AppBar(
        title: const Text(_SoulStrings.title),
        actions: [
          IconButton(
            tooltip: _SoulStrings.previewTooltip,
            icon: Icon(
              isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
            ),
            onPressed: () => ref
                .read(soulEditorControllerProvider.notifier)
                .setEditing(!isEditing),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context, soulAsync, loadError, isEditing, isSaving),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<SoulEditorState> soulAsync,
    String? loadError,
    bool isEditing,
    bool isSaving,
  ) {
    if (soulAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loadError != null) {
      return AppErrorView(
        title: loadError,
        onRetry: () => ref.read(soulEditorControllerProvider.notifier).load(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeBanner(context, isEditing),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: isEditing ? _editor(context) : _preview(context),
          ),
          const SizedBox(height: AppSpacing.md),
          _footerActions(context, isSaving),
        ],
      ),
    );
  }

  Widget _modeBanner(BuildContext context, bool isEditing) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_outlined : Icons.visibility_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            isEditing ? _SoulStrings.editMode : _SoulStrings.previewMode,
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      minLines: 10,
      expands: false,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        hintText: _SoulStrings.hint,
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final text = _controller.text;
    if (text.trim().isEmpty) {
      return Center(
        child: Text(
          _SoulStrings.previewEmpty,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: SelectableText(text, style: textTheme.bodyMedium),
      ),
    );
  }

  Widget _footerActions(BuildContext context, bool isSaving) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            text: _SoulStrings.restore,
            variant: AppButtonVariant.secondary,
            onPressed: _restoreDefault,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppButton(
            text: isSaving ? _SoulStrings.saving : _SoulStrings.save,
            isLoading: isSaving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
