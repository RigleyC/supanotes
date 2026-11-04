// The note editor toolbar: one row above the keyboard with every format.
//
// The row scrolls sideways; the button that hides the keyboard stays pinned
// at its end. Buttons are grouped (lists, inline styles, paragraph styles,
// indentation, insertions, attachments) with dividers between groups.
import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_interaction.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';
import 'package:supanotes/shared/widgets/glass/glass_surface.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

/// Corner radius of the floating toolbar shell.
const _shellRadius = 26.0;

/// Height of a toolbar button.
const _buttonSize = 44.0;

/// Space between two buttons of the same group.
const _buttonGap = 2.0;

/// Rebuilds [builder] with the formatting state of [editorState]'s selection,
/// only when that state changes.
class NoteFormatStateBuilder extends StatefulWidget {
  const NoteFormatStateBuilder({
    required this.editorState,
    required this.builder,
    super.key,
  });

  final EditorState editorState;
  final Widget Function(BuildContext context, NoteFormatState state) builder;

  @override
  State<NoteFormatStateBuilder> createState() => _NoteFormatStateBuilderState();
}

class _NoteFormatStateBuilderState extends State<NoteFormatStateBuilder> {
  late NoteFormatState _state;
  StreamSubscription<Object?>? _transactions;

  @override
  void initState() {
    super.initState();
    _listen(widget.editorState);
  }

  @override
  void didUpdateWidget(NoteFormatStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState) {
      _unlisten(oldWidget.editorState);
      _listen(widget.editorState);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.editorState);
    super.dispose();
  }

  void _listen(EditorState editorState) {
    _state = NoteFormatState.of(editorState);
    editorState.selectionNotifier.addListener(_onStateChange);
    editorState.toggledStyleNotifier.addListener(_onStateChange);
    // Formatting changes the selection's attributes without moving it.
    _transactions = editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) _onStateChange();
    });
  }

  void _unlisten(EditorState editorState) {
    editorState.selectionNotifier.removeListener(_onStateChange);
    editorState.toggledStyleNotifier.removeListener(_onStateChange);
    unawaited(_transactions?.cancel());
    _transactions = null;
  }

  void _onStateChange() {
    if (!mounted) return;
    final next = NoteFormatState.of(widget.editorState);
    if (next == _state) return;
    setState(() => _state = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}

class NoteToolbar extends StatelessWidget {
  const NoteToolbar({
    required this.editorState,
    super.key,
    this.onAttachFile,
    this.onAttachImage,
    this.onHideKeyboard,
    this.onLinkNote,
  });

  final EditorState editorState;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;
  final VoidCallback? onHideKeyboard;

  /// Asks which note the selected text should link to.
  final VoidCallback? onLinkNote;

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: GlassSurface(
          key: const ValueKey('note-toolbar-shell'),
          radius: _shellRadius,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  // A sideways scroll view would otherwise take all the
                  // height it is offered.
                  child: SizedBox(
                    height: _buttonSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_shellRadius - 4),
                      child: SingleChildScrollView(
                        key: const ValueKey('note-toolbar-scroll'),
                        scrollDirection: Axis.horizontal,
                        child: NoteFormatStateBuilder(
                          editorState: editorState,
                          builder: (context, state) => _FormatButtons(
                            editorState: editorState,
                            state: state,
                            onLinkNote: onLinkNote,
                            onAttachImage: onAttachImage,
                            onAttachFile: onAttachFile,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const ToolbarDivider(),
                ToolbarButton(
                  icon: Icons.keyboard_hide_outlined,
                  isActive: false,
                  spacious: true,
                  haptic: ToolbarHaptic.controlTap,
                  onPressed: onHideKeyboard,
                  semanticLabel: 'Esconder teclado',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paragraph styles, drawn as short labels.
const _paragraphButtons = [
  (style: NoteBlockStyle.header1, glyph: 'H1', label: 'Título'),
  (style: NoteBlockStyle.header2, glyph: 'H2', label: 'Cabeçalho'),
  (style: NoteBlockStyle.header3, glyph: 'H3', label: 'Subcabeçalho'),
];

class _FormatButtons extends StatelessWidget {
  const _FormatButtons({
    required this.editorState,
    required this.state,
    required this.onLinkNote,
    required this.onAttachImage,
    required this.onAttachFile,
  });

  final EditorState editorState;
  final NoteFormatState state;
  final VoidCallback? onLinkNote;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  void _toggleBlock(NoteBlockStyle style) =>
      unawaited(editorState.toggleNoteBlockStyle(style));

  ToolbarButton _block(
    NoteBlockStyle style, {
    required String semanticLabel,
    IconData? icon,
    String? svgAsset,
    String? label,
    bool? active,
  }) => ToolbarButton(
    icon: icon,
    svgAsset: svgAsset,
    label: label,
    labelStyle: label == null ? null : _paragraphGlyph,
    isActive: active ?? state.blockStyle == style,
    spacious: true,
    haptic: ToolbarHaptic.selectionChange,
    onPressed: () => _toggleBlock(style),
    semanticLabel: semanticLabel,
  );

  static const _paragraphGlyph = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  ToolbarButton _action(
    IconData icon,
    String semanticLabel,
    VoidCallback? onPressed,
  ) => ToolbarButton(
    icon: icon,
    isActive: false,
    spacious: true,
    haptic: ToolbarHaptic.controlTap,
    onPressed: onPressed,
    semanticLabel: semanticLabel,
  );

  @override
  Widget build(BuildContext context) {
    final groups = <List<Widget>>[
      [
        _block(
          NoteBlockStyle.task,
          svgAsset: 'assets/icons/checkbox.svg',
          active: state.allTasks,
          semanticLabel: 'Tarefa',
        ),
        _block(
          NoteBlockStyle.bulletList,
          icon: Icons.format_list_bulleted,
          semanticLabel: 'Lista com marcadores',
        ),
        _block(
          NoteBlockStyle.orderedList,
          icon: Icons.format_list_numbered,
          semanticLabel: 'Lista numerada',
        ),
      ],
      [
        for (final style in noteInlineStyleButtons)
          ToolbarButton(
            label: style.glyph,
            labelStyle: style.glyphStyle,
            isActive: state.inlineStyles.contains(style.key),
            spacious: true,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: () =>
                unawaited(editorState.toggleNoteInlineStyle(style.key)),
            semanticLabel: style.label,
          ),
      ],
      [
        for (final paragraph in _paragraphButtons)
          _block(
            paragraph.style,
            label: paragraph.glyph,
            semanticLabel: paragraph.label,
          ),
        _block(
          NoteBlockStyle.quote,
          icon: Icons.format_quote_rounded,
          semanticLabel: 'Citação',
        ),
      ],
      [
        _action(
          Icons.format_indent_decrease,
          'Diminuir recuo',
          state.hasListOrTask
              ? () => unawaited(editorState.outdentNoteBlocks())
              : null,
        ),
        _action(
          Icons.format_indent_increase,
          'Aumentar recuo',
          state.hasListOrTask
              ? () => unawaited(editorState.indentNoteBlocks())
              : null,
        ),
      ],
      [
        _action(
          Icons.link,
          'Criar link para outra nota',
          state.hasTextSelection ? onLinkNote : null,
        ),
        _action(
          Icons.horizontal_rule,
          'Inserir divisória',
          () => unawaited(editorState.insertNoteDivider()),
        ),
      ],
      [
        _action(Icons.photo_outlined, 'Anexar foto', onAttachImage),
        _action(Icons.attach_file, 'Anexar arquivo', onAttachFile),
      ],
    ];

    return Row(
      children: [
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const ToolbarDivider(),
          for (final (i, button) in group.indexed) ...[
            if (i > 0) const SizedBox(width: _buttonGap),
            button,
          ],
        ],
      ],
    );
  }
}

/// Bold, italic and strikethrough, drawn as styled letters.
const noteInlineStyleButtons = [
  (
    key: NoteInlineStyle.bold,
    glyph: 'B',
    label: 'Negrito',
    glyphStyle: TextStyle(fontWeight: FontWeight.w800),
  ),
  (
    key: NoteInlineStyle.italic,
    glyph: 'I',
    label: 'Itálico',
    glyphStyle: TextStyle(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w500,
    ),
  ),
  (
    key: NoteInlineStyle.strikethrough,
    glyph: 'S',
    label: 'Tachado',
    glyphStyle: TextStyle(
      decoration: TextDecoration.lineThrough,
      fontWeight: FontWeight.w500,
    ),
  ),
];
