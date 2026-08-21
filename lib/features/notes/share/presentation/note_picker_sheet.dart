import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_input.dart';

/// Bottom sheet that lets the user pick which editable note receives a
/// shared link. Returns the selected note, or null when dismissed.
Future<NoteModel?> showShareNotePickerSheet(
  BuildContext context, {
  required List<NoteModel> notes,
}) {
  return showAppBottomSheet<NoteModel>(
    context: context,
    builder: (_) => ShareNotePickerSheet(notes: notes),
  );
}

class ShareNotePickerSheet extends StatefulWidget {
  const ShareNotePickerSheet({super.key, required this.notes});

  final List<NoteModel> notes;

  @override
  State<ShareNotePickerSheet> createState() => _ShareNotePickerSheetState();
}

class _ShareNotePickerSheetState extends State<ShareNotePickerSheet> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Salvar link em', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        AppInput(
          controller: _queryController,
          hintText: 'Buscar nota',
          prefixIcon: const Icon(Icons.search),
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _PickerResults(
            notes: widget.notes,
            query: _queryController.text,
          ),
        ),
        const SizedBox(height: 8),
        AppButton(
          text: 'Cancelar',
          variant: AppButtonVariant.text,
          width: double.infinity,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

}

class _PickerResults extends StatelessWidget {
  const _PickerResults({required this.notes, required this.query});

  final List<NoteModel> notes;
  final String query;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim().toLowerCase();
    final results = notes
        .where(
          (note) =>
              trimmedQuery.isEmpty ||
              note.title.toLowerCase().contains(trimmedQuery) ||
              (note.excerpt ?? note.content).toLowerCase().contains(
                trimmedQuery,
              ),
        )
        .toList(growable: false);
    if (results.isEmpty) {
      return const Center(child: Text('Nenhuma nota editável encontrada.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final note = results[index];
        return ListTile(
          title: Text(note.title.isEmpty ? 'Sem título' : note.title),
          subtitle: Text(
            note.excerpt ?? note.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(note),
        );
      },
    );
  }
}
