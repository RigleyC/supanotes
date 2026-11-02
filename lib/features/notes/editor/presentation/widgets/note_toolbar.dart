// Compact contextual toolbar for the note editor.
//
// The toolbar derives its content from the editor selection (see
// NoteFormatState). A caret in a paragraph shows block-format controls;
// selecting text or placing the caret in a list/task shows inline and block
// conversion controls. The toolbar shell keeps a single position and height -
// only its action content animates between the two modes.
import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_format_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_interaction.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/glass/glass_surface.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

/// Corner radius of the floating toolbar shell.
const _shellRadius = 30.0;

/// Which row of the note toolbar is shown.
enum NoteToolbarMode { normal, contextual }

/// Contextual for a text selection, or a caret inside a list or task.
NoteToolbarMode noteToolbarModeFor(NoteFormatState state) =>
    state.hasTextSelection || state.hasListOrTask
    ? NoteToolbarMode.contextual
    : NoteToolbarMode.normal;

class NoteToolbar extends StatefulWidget {
  const NoteToolbar({
    required this.editorState,
    super.key,
    this.onAttachFile,
    this.onAttachImage,
  });

  final EditorState editorState;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  State<NoteToolbar> createState() => _NoteToolbarState();
}

class _NoteToolbarState extends State<NoteToolbar> {
  late NoteFormatState _state;
  StreamSubscription<Object?>? _transactions;

  @override
  void initState() {
    super.initState();
    _listen(widget.editorState);
  }

  @override
  void didUpdateWidget(NoteToolbar oldWidget) {
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
  Widget build(BuildContext context) {
    final editorState = widget.editorState;
    return TapRegion(
      groupId: noteEditorToolbarTapRegionGroup,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: GlassSurface(
          key: const ValueKey('note-toolbar-shell'),
          radius: _shellRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 8,
            ),
            child: _ContextualToolbarContent(
              mode: noteToolbarModeFor(_state),
              normalActions: _NormalActions(
                state: _state,
                onSetBlockStyle: (style) =>
                    unawaited(editorState.toggleNoteBlockStyle(style)),
                onInsertDivider: () =>
                    unawaited(editorState.insertNoteDivider()),
                onAttachImage: widget.onAttachImage,
                onAttachFile: widget.onAttachFile,
              ),
              contextualActions: _ContextualActions(
                state: _state,
                onToggleInline: (key) =>
                    unawaited(editorState.toggleNoteInlineStyle(key)),
                onSetBlockStyle: (style) =>
                    unawaited(editorState.toggleNoteBlockStyle(style)),
                onUnindent: () => unawaited(editorState.outdentNoteBlocks()),
                onIndent: () => unawaited(editorState.indentNoteBlocks()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NormalActions extends StatelessWidget {
  const _NormalActions({
    required this.state,
    required this.onSetBlockStyle,
    required this.onInsertDivider,
    required this.onAttachImage,
    required this.onAttachFile,
  });

  final NoteFormatState state;
  final ValueChanged<NoteBlockStyle> onSetBlockStyle;
  final VoidCallback onInsertDivider;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    final blockStyle = state.blockStyle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          svgAsset: 'assets/icons/h1_icon.svg',
          isActive: blockStyle == NoteBlockStyle.header1,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.header1),
          semanticLabel: 'Título 1',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h2_icon.svg',
          isActive: blockStyle == NoteBlockStyle.header2,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.header2),
          semanticLabel: 'Título 2',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h3_icon.svg',
          isActive: blockStyle == NoteBlockStyle.header3,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.header3),
          semanticLabel: 'Título 3',
        ),
        ToolbarButton(
          icon: Icons.format_quote,
          isActive: blockStyle == NoteBlockStyle.quote,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.quote),
          semanticLabel: 'Citação',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.task),
          semanticLabel: 'Task',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.horizontal_rule,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onInsertDivider,
          semanticLabel: 'Inserir divisor',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.image,
          isActive: false,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onAttachImage,
          semanticLabel: 'Inserir imagem',
        ),
        ToolbarButton(
          icon: Icons.attach_file,
          isActive: false,
          haptic: ToolbarHaptic.controlTap,
          onPressed: onAttachFile,
          semanticLabel: 'Anexar arquivo',
        ),
      ],
    );
  }
}

class _ContextualActions extends StatelessWidget {
  const _ContextualActions({
    required this.state,
    required this.onToggleInline,
    required this.onSetBlockStyle,
    required this.onUnindent,
    required this.onIndent,
  });

  final NoteFormatState state;
  final ValueChanged<String> onToggleInline;
  final ValueChanged<NoteBlockStyle> onSetBlockStyle;
  final VoidCallback onUnindent;
  final VoidCallback onIndent;

  @override
  Widget build(BuildContext context) {
    final hasText = state.hasTextSelection;
    final hasListOrTask = state.hasListOrTask;
    final inline = state.inlineStyles;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          icon: Icons.format_bold,
          isActive: inline.contains(NoteInlineStyle.bold),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText
              ? () => onToggleInline(NoteInlineStyle.bold)
              : null,
          semanticLabel: 'Negrito',
        ),
        ToolbarButton(
          icon: Icons.format_italic,
          isActive: inline.contains(NoteInlineStyle.italic),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText
              ? () => onToggleInline(NoteInlineStyle.italic)
              : null,
          semanticLabel: 'Itálico',
        ),
        ToolbarButton(
          icon: Icons.format_strikethrough,
          isActive: inline.contains(NoteInlineStyle.strikethrough),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText
              ? () => onToggleInline(NoteInlineStyle.strikethrough)
              : null,
          semanticLabel: 'Tachado',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.format_list_bulleted,
          isActive: state.blockStyle == NoteBlockStyle.bulletList,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.bulletList),
          semanticLabel: 'Lista com marcadores',
        ),
        ToolbarButton(
          icon: Icons.format_list_numbered,
          isActive: state.blockStyle == NoteBlockStyle.orderedList,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.orderedList),
          semanticLabel: 'Lista numerada',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockStyle(NoteBlockStyle.task),
          semanticLabel: 'Task',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.format_indent_decrease,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasListOrTask ? onUnindent : null,
          semanticLabel: 'Diminuir recuo',
        ),
        ToolbarButton(
          icon: Icons.format_indent_increase,
          isActive: false,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasListOrTask ? onIndent : null,
          semanticLabel: 'Aumentar recuo',
        ),
      ],
    );
  }
}

class _ContextualToolbarContent extends StatefulWidget {
  const _ContextualToolbarContent({
    required this.mode,
    required this.normalActions,
    required this.contextualActions,
  });

  final NoteToolbarMode mode;
  final Widget normalActions;
  final Widget contextualActions;

  @override
  State<_ContextualToolbarContent> createState() =>
      _ContextualToolbarContentState();
}

class _ContextualToolbarContentState extends State<_ContextualToolbarContent>
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
  void didUpdateWidget(_ContextualToolbarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _applyMotion();
    }
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
    final showingNormal = widget.mode == NoteToolbarMode.normal;
    final incoming = showingNormal
        ? widget.normalActions
        : widget.contextualActions;
    final outgoing = showingNormal
        ? widget.contextualActions
        : widget.normalActions;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (_, _) {
          final progress = _motion.value.clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The leaving row is removed from the tree once its fade ends.
              if (progress < 1)
                Positioned(
                  left: 0,
                  top: 0,
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: FadeTransition(
                        opacity: _outgoingOpacity,
                        child: Transform.translate(
                          offset: Offset(-(1 - progress) * 8, 0),
                          child: Transform.scale(
                            scale: 0.96 + 0.04 * progress,
                            alignment: Alignment.centerLeft,
                            child: outgoing,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Opacity(
                opacity: 0.35 + 0.65 * progress,
                child: Transform.translate(
                  offset: Offset((1 - progress) * 8, 0),
                  child: Transform.scale(
                    scale: 0.96 + 0.04 * progress,
                    alignment: Alignment.centerLeft,
                    child: incoming,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
