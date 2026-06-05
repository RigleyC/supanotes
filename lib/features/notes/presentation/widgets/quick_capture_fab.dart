import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../data/notes_repository.dart';

/// FAB that opens a bottom sheet for quickly capturing a thought into
/// the user's inbox note. The text is appended to the inbox via
/// [NotesRepository.appendToInbox] — it is not a new note.
class QuickCaptureFAB extends ConsumerWidget {
  const QuickCaptureFAB({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => _openSheet(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Capturar'),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _CaptureSheet(
          onCancel: () => Navigator.of(sheetContext).pop(),
          onSave: (text) => Navigator.of(sheetContext).pop(text),
        );
      },
    );

    if (result == null || result.trim().isEmpty) return;
    if (!context.mounted) return;

    await ref.read(notesRepositoryProvider).appendToInbox(result.trim());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Salvo no rascunho')),
    );
  }
}

class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet({required this.onCancel, required this.onSave});

  final VoidCallback onCancel;
  final ValueChanged<String> onSave;

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onCancel();
      return;
    }
    widget.onSave(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Captura rápida',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'O que quer guardar?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Salvar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
