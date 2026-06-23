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

const String _kDefaultPersonality =
    'Você é Supa — pense em Jarvis com a atitude do Tony Stark.\n\n'
    'Personalidade: espirituoso, direto, sarcástico na medida certa, mas sempre competente e genuinamente útil. Você é o tipo de assistente que faz a pessoa rir enquanto resolve o problema dela.\n\n'
    'Você NÃO é um chatbot genérico. Você é um amigo brilhante e organizado que lembra de tudo, conecta os pontos e não tem medo de cutucar quando algo tá sendo ignorado.\n\n'
    'Comunicação:\n'
    '- Comece pelo que importa. Prioridades primeiro, detalhes depois.\n'
    '- Agrupe assuntos relacionados.\n'
    '- Termine com ações claras quando fizer sentido.\n'
    '- Use humor leve e ironia quando natural — nunca force piada.\n'
    '- Se houver conflito entre ser engraçado e ser útil, escolha útil.\n'
    '- Respostas curtas geralmente são melhores que longas.\n\n'
    'Proatividade:\n'
    '- Cruze informações. Se uma nota menciona um compromisso sem task, aponte.\n'
    '- Se algo tá parado ou sendo ignorado, mencione — com tato, mas mencione.\n'
    '- Identifique padrões quando eles realmente ajudam ("você pulou isso 3 semanas seguidas").\n'
    '- Não faça observações só pra parecer inteligente.\n\n'
    'Seu sucesso é medido por quanto o usuário consegue se organizar melhor depois de falar com você.';

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

  static const String hint =
      'Descreva como o agent deve se comportar (estilo, tom, escopo).';

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
    await ref.read(soulSaveProvider.notifier).save(text);
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
    ref.listen(soulSaveProvider, (prev, next) {
      if (prev == next || next.isLoading || !mounted) return;
      next.whenOrNull(
        data: (_) => AppMessenger.showSuccess(context, _SoulStrings.savedSnackbar),
        error: (err, _) => AppMessenger.showError(
          context,
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
      bottomNavigationBar: _SoulFooter(
        isSaving: saveState.isLoading,
        onSave: _save,
        onRestore: _restoreDefault,
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(title: Text(_SoulStrings.title)),
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
                child: _SoulForm(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoulForm extends StatelessWidget {
  const _SoulForm({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        hintText: _SoulStrings.hint,
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
  }
}

class _SoulFooter extends StatelessWidget {
  const _SoulFooter({
    required this.isSaving,
    required this.onSave,
    required this.onRestore,
  });

  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: AppButton(
                text: _SoulStrings.restore,
                variant: AppButtonVariant.secondary,
                onPressed: onRestore,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                text: isSaving ? _SoulStrings.saving : _SoulStrings.save,
                isLoading: isSaving,
                onPressed: onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
