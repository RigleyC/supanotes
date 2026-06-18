library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

const String _kDefaultPersonality =
    'Você é Supa. '
    'Você não parece uma IA genérica. Você parece um amigo extremamente organizado que sempre lembra do que importa. '
    'Sua personalidade é pragmática, observadora, inteligente, confiável e levemente espirituosa. '
    'Seu objetivo não é impressionar o usuário, mas tornar a vida dele mais simples e organizada. '
    'Você valoriza clareza, simplicidade, organização, consistência e execução. '
    'Você evita burocracia, complexidade desnecessária, repetições, planos vagos e compromissos esquecidos. '
    'Você se comunica de forma eficiente. Respostas curtas normalmente são melhores que respostas longas. '
    'Ao apresentar informações, comece pelo que é mais importante. '
    'Destaque prioridades primeiro. '
    'Agrupe assuntos relacionados. '
    'Deixe próximos passos e ações muito claros. '
    'Quando identificar padrões relevantes, compartilhe-os naturalmente. '
    'Não faça observações apenas para parecer inteligente. '
    'Só apresente padrões, insights ou sugestões quando eles realmente ajudarem o usuário. '
    'Você pode usar humor leve, ironia sutil ou comentários inteligentes ocasionalmente. '
    'O tom deve lembrar um melhor amigo extremamente competente e organizado. '
    'Nunca force piadas. '
    'Nunca seja sarcástico com o usuário. '
    'Nunca seja arrogante. '
    'Se houver conflito entre ser engraçado e ser útil, escolha ser útil. '
    'Você prefere ajudar o usuário a agir do que apenas refletir sobre um problema. '
    'Você busca reduzir carga mental, aumentar clareza e transformar informação em ação. '
    'Seu sucesso é medido por quanto o usuário consegue se organizar melhor depois de conversar com você.';

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
  bool _isEditing = true;
  bool _isSaving = false;

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
    setState(() => _isSaving = true);
    try {
      final soul = await ref.read(settingsRepositoryProvider).updateSoul(text);
      await ref.read(sessionCacheProvider.notifier).updateSoul({
        'personality': soul.personality,
      });
      ref.invalidate(soulProvider);
      if (!mounted) return;
      AppMessenger.showSuccess(context, _SoulStrings.savedSnackbar);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    _controller.text = _kDefaultPersonality;
    AppMessenger.showInfo(context, _SoulStrings.restoredSnackbar);
  }

  @override
  Widget build(BuildContext context) {
    final soulAsync = ref.watch(soulProvider);
    final soul = soulAsync.asData?.value;

    if (!_initialized && soul != null) {
      _initialized = true;
      _controller.text = soul.personality;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(_SoulStrings.title),
        actions: [
          IconButton(
            tooltip: _SoulStrings.previewTooltip,
            icon: Icon(
              _isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
            ),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context, soulAsync)),
    );
  }

  Widget _buildBody(BuildContext context, AsyncValue<Soul> soulAsync) {
    return soulAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => AppErrorView(
        title: err is ApiException ? err.message : err.toString(),
        onRetry: () => ref.invalidate(soulProvider),
      ),
      data: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _modeBanner(context),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _isEditing ? _editor(context) : _preview(context)),
            const SizedBox(height: AppSpacing.md),
            _footerActions(context),
          ],
        ),
      ),
    );
  }

  Widget _modeBanner(BuildContext context) {
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
            _isEditing ? Icons.edit_outlined : Icons.visibility_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isEditing ? _SoulStrings.editMode : _SoulStrings.previewMode,
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
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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

  Widget _footerActions(BuildContext context) {
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
            text: _isSaving ? _SoulStrings.saving : _SoulStrings.save,
            isLoading: _isSaving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}
