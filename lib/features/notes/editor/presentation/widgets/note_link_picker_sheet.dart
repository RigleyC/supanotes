import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/application/note_suggestion_provider.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';

/// Asks which note to link to; null when the user cancels.
Future<NoteModel?> pickNoteToLink(
  BuildContext context, {
  required String currentNoteId,
}) => showAppBottomSheet<NoteModel>(
  context: context,
  builder: (_) => _NoteLinkPicker(currentNoteId: currentNoteId),
);

class _NoteLinkPicker extends ConsumerStatefulWidget {
  const _NoteLinkPicker({required this.currentNoteId});

  final String currentNoteId;

  @override
  ConsumerState<_NoteLinkPicker> createState() => _NoteLinkPickerState();
}

class _NoteLinkPickerState extends ConsumerState<_NoteLinkPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(
      noteSuggestionsProvider((
        query: _query,
        currentNoteId: widget.currentNoteId,
      )),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Buscar nota',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Flexible(
          child: notes.when(
            data: (notes) => notes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma nota encontrada',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          note.title.isEmpty ? 'Sem título' : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(note),
                      );
                    },
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Não foi possível carregar as notas',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
