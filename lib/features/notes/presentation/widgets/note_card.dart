import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/note_model.dart';

/// Card representation of a single [NoteModel] in the notes list.
///
/// Stateless layout: title (bold, single line) + excerpt (2 lines,
/// muted) + footer (favorite star, context chip, relative timestamp).
/// Swipe-to-delete and long-press are wired in the parent list so the
/// `Dismissible` and `showModalBottomSheet` plumbing does not pollute
/// the row itself.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final NoteModel note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  static const _fallbackTitle = 'Sem título';

  String? _resolveExcerpt(NoteModel note) {
    if (note.excerpt != null && note.excerpt!.trim().isNotEmpty) {
      return note.excerpt!.trim();
    }
    if (note.content.isEmpty) return null;
    final flat = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 120) return flat;
    return '${flat.substring(0, 120)}…';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = note.title?.trim().isNotEmpty == true
        ? note.title!.trim()
        : _fallbackTitle;
    final excerpt = _resolveExcerpt(note);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showActions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.favorite)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Icon(
                        Icons.star,
                        size: 18,
                        color: scheme.tertiary,
                      ),
                    ),
                ],
              ),
              if (excerpt != null && excerpt.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  excerpt,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _Footer(note: note),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  note.favorite ? Icons.star_border : Icons.star,
                ),
                title: Text(
                  note.favorite ? 'Desfavoritar' : 'Favoritar',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onToggleFavorite();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Apagar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.note});

  final NoteModel note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Row(
      children: [
        if (note.contextId != null) ...[
          _ContextChip(label: note.contextId!),
          const SizedBox(width: AppSpacing.sm),
        ],
        const Spacer(),
        Text(timeago.format(note.updatedAt, locale: 'pt_BR'), style: muted),
      ],
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Wraps [child] in a [Dismissible] configured for swipe-to-delete with
/// a confirm dialog. Lives next to [NoteCard] so the list builder can
/// call it as `DismissibleDeleteWrapper(child: NoteCard(...))`.
class DismissibleDeleteWrapper extends StatelessWidget {
  const DismissibleDeleteWrapper({
    super.key,
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(child.key ?? child.hashCode),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Apagar nota?'),
              content: const Text('Esta ação pode ser revertida na sincronização.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Apagar'),
                ),
              ],
            );
          },
        );
        if (confirmed == true) {
          await onDelete();
          return true;
        }
        return false;
      },
      child: child,
    );
  }
}
