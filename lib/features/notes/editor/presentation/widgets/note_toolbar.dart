// The note editor toolbar: one row above the keyboard.
//
// With a caret it offers what is used while writing (format panel, task,
// bullets, photo, file, hide keyboard). With selected text it switches to
// what applies to that text (bold, italic, strikethrough, task, note link and
// the format panel). Everything else lives in the "Formatar" panel, which
// takes the keyboard's place (see NoteFormatPanel). The bar keeps its
// position and height; only its row animates between the two modes.
import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_interaction.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';
import 'package:supanotes/shared/widgets/glass/glass_surface.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

/// Corner radius of the floating toolbar shell.
const _shellRadius = 26.0;

/// Which row of the note toolbar is shown.
enum NoteToolbarMode { writing, selection }

/// The selection row while text is selected, the writing row otherwise.
NoteToolbarMode noteToolbarModeFor(NoteFormatState state) =>
    state.hasTextSelection
    ? NoteToolbarMode.selection
    : NoteToolbarMode.writing;

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
    this.panelOpen = false,
    this.onTogglePanel,
    this.onAttachFile,
    this.onAttachImage,
    this.onHideKeyboard,
    this.onLinkNote,
  });

  final EditorState editorState;

  /// Whether the "Formatar" panel is showing in the keyboard's place.
  final bool panelOpen;
  final VoidCallback? onTogglePanel;
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
            child: NoteFormatStateBuilder(
              editorState: editorState,
              builder: (context, state) => _ToolbarRows(
                mode: noteToolbarModeFor(state),
                writing: _WritingRow(
                  state: state,
                  panelOpen: panelOpen,
                  onTogglePanel: onTogglePanel,
                  onToggleTask: () => unawaited(
                    editorState.toggleNoteBlockStyle(NoteBlockStyle.task),
                  ),
                  onToggleBullets: () => unawaited(
                    editorState.toggleNoteBlockStyle(NoteBlockStyle.bulletList),
                  ),
                  onAttachImage: onAttachImage,
                  onAttachFile: onAttachFile,
                  onHideKeyboard: onHideKeyboard,
                ),
                selection: _SelectionRow(
                  state: state,
                  panelOpen: panelOpen,
                  onToggleInline: (key) =>
                      unawaited(editorState.toggleNoteInlineStyle(key)),
                  onToggleTask: () => unawaited(
                    editorState.toggleNoteBlockStyle(NoteBlockStyle.task),
                  ),
                  onLinkNote: onLinkNote,
                  onTogglePanel: onTogglePanel,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WritingRow extends StatelessWidget {
  const _WritingRow({
    required this.state,
    required this.panelOpen,
    required this.onTogglePanel,
    required this.onToggleTask,
    required this.onToggleBullets,
    required this.onAttachImage,
    required this.onAttachFile,
    required this.onHideKeyboard,
  });

  final NoteFormatState state;
  final bool panelOpen;
  final VoidCallback? onTogglePanel;
  final VoidCallback onToggleTask;
  final VoidCallback onToggleBullets;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;
  final VoidCallback? onHideKeyboard;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ToolbarButton(
          label: 'Aa',
          isActive: panelOpen,
          activeStyle: ToolbarActiveStyle.filled,
          spacious: true,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onTogglePanel,
          semanticLabel: 'Formatar',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          spacious: true,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onToggleTask,
          semanticLabel: 'Inserir tarefa',
        ),
        ToolbarButton(
          icon: Icons.format_list_bulleted,
          isActive: state.blockStyle == NoteBlockStyle.bulletList,
          spacious: true,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onToggleBullets,
          semanticLabel: 'Lista com marcadores',
        ),
        ToolbarButton(
          icon: Icons.photo_outlined,
          isActive: false,
          spacious: true,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onAttachImage,
          semanticLabel: 'Anexar foto',
        ),
        ToolbarButton(
          icon: Icons.attach_file,
          isActive: false,
          spacious: true,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onAttachFile,
          semanticLabel: 'Anexar arquivo',
        ),
        ToolbarButton(
          icon: Icons.keyboard_hide_outlined,
          isActive: false,
          spacious: true,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onHideKeyboard,
          semanticLabel: 'Esconder teclado',
        ),
      ],
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.state,
    required this.panelOpen,
    required this.onToggleInline,
    required this.onToggleTask,
    required this.onLinkNote,
    required this.onTogglePanel,
  });

  final NoteFormatState state;
  final bool panelOpen;
  final ValueChanged<String> onToggleInline;
  final VoidCallback onToggleTask;
  final VoidCallback? onLinkNote;
  final VoidCallback? onTogglePanel;

  @override
  Widget build(BuildContext context) {
    final inline = state.inlineStyles;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final style in noteInlineStyleButtons)
          ToolbarButton(
            label: style.glyph,
            labelStyle: style.glyphStyle,
            isActive: inline.contains(style.key),
            spacious: true,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: () => onToggleInline(style.key),
            semanticLabel: style.label,
          ),
        const ToolbarDivider(),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          spacious: true,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onToggleTask,
          semanticLabel: 'Transformar em tarefa',
        ),
        ToolbarButton(
          icon: Icons.link,
          isActive: false,
          spacious: true,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onLinkNote,
          semanticLabel: 'Criar link para outra nota',
        ),
        ToolbarButton(
          label: 'Aa',
          isActive: panelOpen,
          activeStyle: ToolbarActiveStyle.filled,
          spacious: true,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onTogglePanel,
          semanticLabel: 'Mais formatação',
        ),
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

/// Shows the row for [mode] across the bar's full width, sliding between
/// rows when the mode changes.
class _ToolbarRows extends StatefulWidget {
  const _ToolbarRows({
    required this.mode,
    required this.writing,
    required this.selection,
  });

  final NoteToolbarMode mode;
  final Widget writing;
  final Widget selection;

  @override
  State<_ToolbarRows> createState() => _ToolbarRowsState();
}

class _ToolbarRowsState extends State<_ToolbarRows>
    with TickerProviderStateMixin {
  late final SingleMotionController _motion;

  /// Fades the leaving row out as the motion runs from 0 to 1.
  late final Animation<double> _outgoingOpacity;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _motion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: 1,
    );
    _outgoingOpacity = ReverseAnimation(_motion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled != _animationsDisabled) {
      _animationsDisabled = disabled;
      _applyMotion();
    }
  }

  @override
  void didUpdateWidget(_ToolbarRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _applyMotion();
  }

  void _applyMotion() {
    if (_animationsDisabled) {
      _motion.value = 1;
      return;
    }
    _motion.value = 0;
    unawaited(_motion.animateTo(1).orCancel.catchError((_) {}));
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final writing = widget.mode == NoteToolbarMode.writing;
    final incoming = writing ? widget.writing : widget.selection;
    final outgoing = writing ? widget.selection : widget.writing;

    return AnimatedBuilder(
      animation: _motion,
      builder: (_, _) {
        final progress = _motion.value.clamp(0.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The leaving row is removed from the tree once its fade ends.
            if (progress < 1)
              Positioned.fill(
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: FadeTransition(
                      opacity: _outgoingOpacity,
                      child: Transform.translate(
                        offset: Offset(-(1 - progress) * 8, 0),
                        child: outgoing,
                      ),
                    ),
                  ),
                ),
              ),
            Opacity(
              opacity: 0.35 + 0.65 * progress,
              child: Transform.translate(
                offset: Offset((1 - progress) * 8, 0),
                child: incoming,
              ),
            ),
          ],
        );
      },
    );
  }
}
