/// Screen for editing the user's SOUL — the persona prompt the agent
/// is conditioned on.
///
/// Two modes are toggled from the app bar:
///   * Edit (default): a multi-line [TextField] bound to a local
///     [TextEditingController]. The "Salvar" button posts via
///     [SettingsRepository.updateSoul].
///   * View: the same text rendered as plain [SelectableText]. We
///     intentionally avoid a markdown renderer here because adding a
///     new dependency is out of scope; the body is still selectable so
///     the user can copy it into another tool if they want a preview.
///
/// "Restaurar padrão" replaces the buffer with [_kDefaultPersonality]
/// after a confirm dialog. The default is the same short Portuguese
/// stub the backend would otherwise see on first login.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

/// Strings displayed on the soul editor screen.
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
  static const String emptyError =
      'A personalidade não pode ficar vazia.';
}

/// The default persona used by "Restaurar padrão".
///
/// Kept short and neutral so the agent has *some* identity even when the
/// user has no opinion. The backend may overwrite this later from its
/// own seed; until then it's the canonical client-side default.
const String _kDefaultPersonality =
    'Você é um assistente pessoal direto, calmo e útil. Respeita o tempo do '
    'usuário, oferece próximos passos claros e não inventa informações.';

class SoulEditorScreen extends ConsumerStatefulWidget {
  const SoulEditorScreen({super.key});

  @override
  ConsumerState<SoulEditorScreen> createState() => _SoulEditorScreenState();
}

class _SoulEditorScreenState extends ConsumerState<SoulEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _editing = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final soul = await ref.read(settingsRepositoryProvider).getSoul();
      if (!mounted) return;
      _controller.text = soul.personality;
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showSnackBar(_SoulStrings.emptyError);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).updateSoul(text);
      if (!mounted) return;
      _showSnackBar(_SoulStrings.savedSnackbar);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
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
    setState(() {
      _editing = true;
    });
    _showSnackBar(_SoulStrings.restoredSnackbar);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_SoulStrings.title),
        actions: [
          IconButton(
            tooltip: _SoulStrings.previewTooltip,
            icon: Icon(
              _editing ? Icons.visibility_outlined : Icons.edit_outlined,
            ),
            onPressed: _loading ? null : () => setState(() => _editing = !_editing),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeBanner(context),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _editing ? _editor(context) : _preview(context)),
          const SizedBox(height: AppSpacing.md),
          _footerActions(context),
        ],
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
            _editing ? Icons.edit_outlined : Icons.visibility_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _editing ? _SoulStrings.editMode : _SoulStrings.previewMode,
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

  Widget _footerActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _restoreDefault,
            icon: const Icon(Icons.restart_alt),
            label: const Text(_SoulStrings.restore),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? _SoulStrings.saving : _SoulStrings.save),
          ),
        ),
      ],
    );
  }
}
