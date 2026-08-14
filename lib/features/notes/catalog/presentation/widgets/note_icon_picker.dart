import 'dart:math' as math;

import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:unicode_emojis/unicode_emojis.dart';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_catalog.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

part 'note_icon_picker_components.dart';

Future<void> showNoteIconPicker({
  required BuildContext context,
  required NoteModel note,
  required Future<void> Function(NoteIcon? icon) onSelected,
}) async {
  if (note.isReadOnly) return;
  await showGlobalSheet<void>(
    context: context,
    builder: (_) => NoteIconPickerRootPage(note: note, onSelected: onSelected),
  );
}

class NoteIconPickerRootPage extends StatelessWidget {
  const NoteIconPickerRootPage({
    super.key,
    required this.note,
    required this.onSelected,
  });

  final NoteModel note;
  final Future<void> Function(NoteIcon? icon) onSelected;

  Future<void> _select(NoteIcon? icon) async {
    await onSelected(icon);
  }

  @override
  Widget build(BuildContext context) {
    final hasIcon = note.noteIcon != null;
    return GlobalSheetPage(
      title: 'Selecionar ícone',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PickerAction(
              icon: Icons.emoji_emotions_outlined,
              label: 'Usar emoji',
              onTap: () => FamilyModalSheet.of(context).pushPage(
                NoteEmojiPickerPage(
                  current: note.noteIcon,
                  onSelected: _select,
                  dismissOnSelection: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _PickerAction(
              icon: Icons.star_outline_rounded,
              label: 'Usar ícone',
              onTap: () => FamilyModalSheet.of(context).pushPage(
                NoteCatalogIconPickerPage(
                  current: note.noteIcon,
                  onSelected: _select,
                  dismissOnSelection: true,
                ),
              ),
            ),
            if (hasIcon)
            ...[
              const SizedBox(height: 8),
                _PickerAction(
                icon: Icons.remove_circle_outline,
                label: 'Remover ícone',
                onTap: () => _select(null),
              ),]
          ],
        ),
      ),
    );
  }
}

class NoteEmojiPickerPage extends StatefulWidget {
  const NoteEmojiPickerPage({
    super.key,
    this.current,
    required this.onSelected,
    this.dismissOnSelection = false,
  });

  final NoteIcon? current;
  final Future<void> Function(NoteIcon icon) onSelected;
  final bool dismissOnSelection;

  @override
  State<NoteEmojiPickerPage> createState() => _NoteEmojiPickerPageState();
}

class _NoteEmojiPickerPageState extends State<NoteEmojiPickerPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emojis = _query.isEmpty
        ? UnicodeEmojis.allEmojis
        : UnicodeEmojis.search(_query, limit: 240);
    return GlobalSheetPage(
      title: 'Escolher emoji',
      contentPadding: EdgeInsets.zero,
      child: _PickerGridContent(
        headerChildren: [
          AppInput(
            controller: _searchController,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar emojis',
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ],
        itemCount: emojis.length,
        itemBuilder: (context, index) {
          final emoji = emojis[index];
          return Semantics(
            button: true,
            label: emoji.name,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final selected =
                    widget.current?.isEmoji == true &&
                    widget.current!.value == emoji.emoji;
                if (selected) return;
                AppHaptics.selectionChange();
                await widget.onSelected(NoteIcon.emoji(emoji.emoji));
                if (widget.dismissOnSelection && context.mounted) {
                  dismissGlobalSheet(context);
                }
              },
              child: Center(
                child: Text(emoji.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NoteCatalogIconPickerPage extends StatefulWidget {
  const NoteCatalogIconPickerPage({
    super.key,
    required this.current,
    required this.onSelected,
    this.dismissOnSelection = false,
  });

  final NoteIcon? current;
  final Future<void> Function(NoteIcon icon) onSelected;
  final bool dismissOnSelection;

  @override
  State<NoteCatalogIconPickerPage> createState() =>
      _NoteCatalogIconPickerPageState();
}

class _NoteCatalogIconPickerPageState extends State<NoteCatalogIconPickerPage> {
  final _searchController = TextEditingController();
  late String _colorKey = widget.current?.colorKey ?? noteIconColors.keys.first;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = catalogIcons.entries.where((entry) {
      if (_query.isEmpty) return true;
      return (catalogIconLabels[entry.key] ?? entry.key).toLowerCase().contains(
        _query.toLowerCase(),
      );
    }).toList();
    final scheme = Theme.of(context).colorScheme;
    return GlobalSheetPage(
      title: 'Escolher ícone',
      contentPadding: EdgeInsets.zero,
      child: _PickerGridContent(
        headerChildren: [
          AppInput(
            controller: _searchController,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar ícones',
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: noteIconColors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final key = noteIconColors.keys.elementAt(index);
                final selected = key == _colorKey;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: 'Cor ${key == 'gray' ? 'cinza' : key}',
                  child: SizedBox.square(
                    dimension: 48,
                    child: InkWell(
                      onTap: () {
                        if (key == _colorKey) return;
                        AppHaptics.selectionChange();
                        setState(() => _colorKey = key);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: noteIconColors[key]!.resolve(
                              scheme.brightness,
                            ),
                            border: selected
                                ? Border.all(color: scheme.onSurface, width: 3)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Semantics(
            button: true,
            label: catalogIconLabels[entry.key] ?? entry.key,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final selected =
                    widget.current?.isEmoji == false &&
                    widget.current!.value == entry.key &&
                    widget.current!.colorKey == _colorKey;
                if (selected) return;
                AppHaptics.selectionChange();
                await widget.onSelected(
                  NoteIcon.catalog(id: entry.key, colorKey: _colorKey),
                );
                if (widget.dismissOnSelection && context.mounted) {
                  dismissGlobalSheet(context);
                }
              },
              child: Icon(
                entry.value,
                size: 28,
                color: noteIconColors[_colorKey]!.resolve(scheme.brightness),
              ),
            ),
          );
        },
      ),
    );
  }
}
