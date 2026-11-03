import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supanotes/core/utils/app_haptics.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_interaction.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar.dart';

/// Paragraph styles offered as a row of chips, previewed in their own size.
const _blockChips = [
  (
    style: NoteBlockStyle.header1,
    label: 'Título',
    size: 20.0,
    weight: FontWeight.w700,
  ),
  (
    style: NoteBlockStyle.header2,
    label: 'Cabeçalho',
    size: 17.0,
    weight: FontWeight.w700,
  ),
  (
    style: NoteBlockStyle.header3,
    label: 'Subcabeçalho',
    size: 15.0,
    weight: FontWeight.w600,
  ),
  (
    style: NoteBlockStyle.paragraph,
    label: 'Corpo',
    size: 15.0,
    weight: FontWeight.w400,
  ),
  (
    style: NoteBlockStyle.quote,
    label: 'Citação',
    size: 15.0,
    weight: FontWeight.w400,
  ),
];

/// The "Formatar" panel, shown in the keyboard's place: paragraph styles,
/// inline styles, indentation, lists, tasks and dividers.
class NoteFormatPanel extends StatelessWidget {
  const NoteFormatPanel({
    required this.editorState,
    required this.height,
    required this.onClose,
    super.key,
  });

  final EditorState editorState;

  /// The keyboard's height, so the note does not jump when they swap.
  final double height;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Container(
        key: const ValueKey('note-format-panel'),
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: NoteFormatStateBuilder(
              editorState: editorState,
              builder: (context, state) => _PanelContent(
                editorState: editorState,
                state: state,
                onClose: onClose,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.editorState,
    required this.state,
    required this.onClose,
  });

  final EditorState editorState;
  final NoteFormatState state;
  final VoidCallback onClose;

  void _run(Future<void> Function() command) {
    AppHaptics.selectionChange();
    unawaited(command());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final blockStyle = state.blockStyle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Formatar',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Fechar formatação',
              child: Material(
                color: scheme.surfaceContainerHighest,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClose,
                  child: const SizedBox.square(
                    dimension: 32,
                    child: Icon(Icons.close, size: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _BlockChips(
          selected: blockStyle,
          onPick: (style) => _run(() => editorState.setNoteBlockStyle(style)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Segmented(
                children: [
                  for (final style in noteInlineStyleButtons)
                    _Tile(
                      selected: state.inlineStyles.contains(style.key),
                      semanticLabel: style.label,
                      onTap: () => _run(
                        () => editorState.toggleNoteInlineStyle(style.key),
                      ),
                      child: Text(
                        style.glyph,
                        style: style.glyphStyle.copyWith(fontSize: 18),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Segmented(
                children: [
                  _Tile(
                    semanticLabel: 'Diminuir recuo',
                    onTap: state.hasListOrTask
                        ? () => _run(editorState.outdentNoteBlocks)
                        : null,
                    child: const Icon(Icons.format_indent_decrease),
                  ),
                  _Tile(
                    semanticLabel: 'Aumentar recuo',
                    onTap: state.hasListOrTask
                        ? () => _run(editorState.indentNoteBlocks)
                        : null,
                    child: const Icon(Icons.format_indent_increase),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (index, item) in [
              (
                glyph: const Icon(Icons.format_list_bulleted),
                label: 'Marcadores',
                semantic: 'Lista com marcadores',
                active: blockStyle == NoteBlockStyle.bulletList,
                run: () => editorState.toggleNoteBlockStyle(
                  NoteBlockStyle.bulletList,
                ),
              ),
              (
                glyph: const Icon(Icons.format_list_numbered),
                label: 'Numerada',
                semantic: 'Lista numerada',
                active: blockStyle == NoteBlockStyle.orderedList,
                run: () => editorState.toggleNoteBlockStyle(
                  NoteBlockStyle.orderedList,
                ),
              ),
              (
                glyph: const NoteTaskGlyph(),
                label: 'Tarefas',
                semantic: 'Lista de tarefas',
                active: state.allTasks,
                run: () =>
                    editorState.toggleNoteBlockStyle(NoteBlockStyle.task),
              ),
              (
                glyph: const Icon(Icons.horizontal_rule),
                label: 'Divisória',
                semantic: 'Inserir divisória',
                active: false,
                run: editorState.insertNoteDivider,
              ),
            ].indexed) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  selected: item.active,
                  semanticLabel: item.semantic,
                  height: 56,
                  onTap: () => _run(item.run),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme.merge(
                        data: IconThemeData(color: scheme.primary, size: 22),
                        child: item.glyph,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The paragraph style chips, scrolled so the current style is visible.
class _BlockChips extends StatefulWidget {
  const _BlockChips({required this.selected, required this.onPick});

  final NoteBlockStyle? selected;
  final ValueChanged<NoteBlockStyle> onPick;

  @override
  State<_BlockChips> createState() => _BlockChipsState();
}

class _BlockChipsState extends State<_BlockChips> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(_BlockChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedKey.currentContext;
      if (context == null) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, chip) in _blockChips.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            _Tile(
              key: widget.selected == chip.style ? _selectedKey : null,
              selected: widget.selected == chip.style,
              filledWhenSelected: true,
              semanticLabel: chip.label,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onTap: () => widget.onPick(chip.style),
              child: Text(
                chip.label,
                style: TextStyle(
                  fontSize: chip.size,
                  fontWeight: chip.weight,
                  color: widget.selected == chip.style
                      ? scheme.onPrimary
                      : scheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The task checkbox drawn as in the toolbar.
class NoteTaskGlyph extends StatelessWidget {
  const NoteTaskGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SvgPicture.asset(
      'assets/icons/checkbox.svg',
      width: theme.size,
      height: theme.size,
      colorFilter: ColorFilter.mode(
        theme.color ?? Colors.black,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Buttons joined into one rounded group.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Row(
      children: [for (final child in children) Expanded(child: child)],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.semanticLabel,
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.filledWhenSelected = false,
    this.height = 44,
    this.padding = EdgeInsets.zero,
  });

  final String semanticLabel;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  /// Selected chips are filled with the accent; other tiles get a tint.
  final bool filledWhenSelected;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = !selected
        ? scheme.surfaceContainerLowest
        : filledWhenSelected
        ? scheme.primary
        : scheme.primaryContainer;
    final foreground = onTap == null
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected && !filledWhenSelected
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: height,
            padding: padding,
            alignment: Alignment.center,
            child: IconTheme.merge(
              data: IconThemeData(color: foreground, size: 22),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
