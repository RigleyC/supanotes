library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';

final _tagsForNoteProvider = StreamProvider.family<List<TagData>, String>((ref, noteId) {
  return ref.watch(tagsDaoProvider).watchTagsForNote(noteId);
});

class NoteTagsChipBar extends ConsumerWidget {
  final String noteId;

  const NoteTagsChipBar({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(_tagsForNoteProvider(noteId));

    return tagsAsync.when(
      data: (tags) => _buildChipBar(context, ref, tags),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildChipBar(BuildContext context, WidgetRef ref, List<TagData> tags) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags.map((tag) => Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    ref.read(tagsDaoProvider).detachTag(
                      noteId: noteId,
                      tagId: tag.id,
                    );
                  },
                )).toList(),
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showTagPicker(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline.withAlpha(80)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'Tag',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTagPicker(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(authControllerProvider).value?.id;
    if (userId == null) return;

    final tagsDao = ref.read(tagsDaoProvider);
    final allTags = await tagsDao.watchTags(userId).first;
    final noteTags = await tagsDao.watchTagsForNote(noteId).first;
    final attachedIds = noteTags.map((t) => t.id).toSet();

    if (!context.mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Adicionar tag'),
        children: allTags.map((tag) {
          final attached = attachedIds.contains(tag.id);
          return SimpleDialogOption(
            onPressed: attached ? null : () => Navigator.of(ctx).pop(tag.id),
            child: Row(
              children: [
                Expanded(child: Text(tag.name)),
                if (attached)
                  Icon(Icons.check, size: 18, color: Theme.of(ctx).colorScheme.primary),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (result != null) {
      await tagsDao.attachTag(noteId: noteId, tagId: result);
    }
  }
}
