import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:unicode_emojis/unicode_emojis.dart';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/shared/widgets/app_icon_button.dart';
import 'package:supanotes/shared/widgets/app_input.dart';

Future<void> showNoteIconPicker({
  required BuildContext context,
  required NoteModel note,
  required Future<void> Function(NoteIcon? icon) onSelected,
}) async {
  if (note.isReadOnly) return;
  await FamilyModalSheet.show<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    contentBackgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (_) => NoteIconPickerRootPage(
      note: note,
      onSelected: onSelected,
    ),
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

  Future<void> _select(BuildContext context, NoteIcon? icon) async {
    await onSelected(icon);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasIcon = note.noteIcon != null;
    return _PickerPage(
      title: 'Selecionar ícone',
      children: [
        _PickerAction(
          icon: Icons.emoji_emotions_outlined,
          label: 'Usar emoji',
          onTap: () => FamilyModalSheet.of(context).pushPage(
            NoteEmojiPickerPage(onSelected: (icon) => _select(context, icon)),
          ),
        ),
        _PickerAction(
          icon: Icons.star_outline_rounded,
          label: 'Usar ícone',
          onTap: () => FamilyModalSheet.of(context).pushPage(
            NoteCatalogIconPickerPage(
              current: note.noteIcon,
              onSelected: (icon) => _select(context, icon),
            ),
          ),
        ),
        if (hasIcon)
          _PickerAction(
            icon: Icons.remove_circle_outline,
            label: 'Remover ícone',
            onTap: () => _select(context, null),
          ),
      ],
    );
  }
}

class NoteEmojiPickerPage extends StatefulWidget {
  const NoteEmojiPickerPage({super.key, required this.onSelected});

  final Future<void> Function(NoteIcon icon) onSelected;

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
        ? UnicodeEmojis.allEmojis.toList()
        : UnicodeEmojis.search(_query, limit: 240);
    return _PickerPage(
      title: 'Escolher emoji',
      onBack: () => FamilyModalSheet.of(context).popPage(),
      children: [
        AppInput(
          controller: _searchController,
          prefixIcon: const Icon(Icons.search),
          hintText: 'Buscar emojis',
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: emojis.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final emoji = emojis[index];
            return Semantics(
              button: true,
              label: emoji.name,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onSelected(NoteIcon.emoji(emoji.emoji)),
                child: Center(
                  child: Text(emoji.emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class NoteCatalogIconPickerPage extends StatefulWidget {
  const NoteCatalogIconPickerPage({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final NoteIcon? current;
  final Future<void> Function(NoteIcon icon) onSelected;

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
      return (catalogIconLabels[entry.key] ?? entry.key)
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList();
    final scheme = Theme.of(context).colorScheme;
    return _PickerPage(
      title: 'Escolher ícone',
      onBack: () => FamilyModalSheet.of(context).popPage(),
      children: [
        AppInput(
          controller: _searchController,
          prefixIcon: const Icon(Icons.search),
          hintText: 'Buscar ícones',
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
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
                child: InkWell(
                  onTap: () => setState(() => _colorKey = key),
                  borderRadius: BorderRadius.circular(21),
                  child: Container(
                    width: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: noteIconColors[key]!.resolve(scheme.brightness),
                      border: selected
                          ? Border.all(color: scheme.onSurface, width: 3)
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 8,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Semantics(
              button: true,
              label: catalogIconLabels[entry.key] ?? entry.key,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onSelected(
                  NoteIcon.catalog(id: entry.key, colorKey: _colorKey),
                ),
                child: Icon(
                  entry.value,
                  size: 28,
                  color: noteIconColors[_colorKey]!.resolve(scheme.brightness),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PickerPage extends StatelessWidget {
  const _PickerPage({
    required this.title,
    required this.children,
    this.onBack,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (onBack != null)
                    AppIconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const Divider(),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerAction extends StatelessWidget {
  const _PickerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
