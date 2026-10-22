// Compact contextual toolbar for the note editor.
//
// The toolbar derives its content from the editor selection and active nodes
// (see NoteToolbarState). A paragraph-level interaction shows block-format
// controls; selecting text or placing the caret in a list/task shows inline and
// block conversion controls. The toolbar shell keeps a single position and
// height - only its action content animates between the two modes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';
import 'package:supanotes/features/notes/editor/document/note_editor_commands.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_editor_interaction.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_button.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_toolbar_state.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/glass/glass_surface.dart';
import 'package:super_editor/super_editor.dart';

export 'note_editor_interaction.dart' show noteEditorToolbarTapRegionGroup;

/// Corner radius of the floating toolbar shell.
const _shellRadius = 30.0;

class NoteToolbar extends StatefulWidget {
  const NoteToolbar({
    required this.editor,
    required this.composer,
    super.key,
    this.onAttachFile,
    this.onAttachImage,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  State<NoteToolbar> createState() => _NoteToolbarState();
}

class _NoteToolbarState extends State<NoteToolbar> {
  late NoteToolbarState _state;

  @override
  void initState() {
    super.initState();
    _state = _readState();
    widget.composer.selectionNotifier.addListener(_onStateChange);
    widget.editor.context.document.addListener(_onStateChange);
  }

  @override
  void didUpdateWidget(NoteToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer) {
      oldWidget.composer.selectionNotifier.removeListener(_onStateChange);
      widget.composer.selectionNotifier.addListener(_onStateChange);
    }
    if (oldWidget.editor != widget.editor) {
      oldWidget.editor.context.document.removeListener(_onStateChange);
      widget.editor.context.document.addListener(_onStateChange);
    }
    _onStateChange();
  }

  @override
  void dispose() {
    widget.composer.selectionNotifier.removeListener(_onStateChange);
    widget.editor.context.document.removeListener(_onStateChange);
    super.dispose();
  }

  NoteToolbarState _readState() => NoteToolbarState.from(
    widget.editor.context.document,
    widget.composer.selection,
  );

  void _onStateChange([DocumentChangeLog? _]) {
    if (!mounted) return;
    final next = _readState();
    if (next == _state) return;
    setState(() => _state = next);
  }

  @override
  Widget build(BuildContext context) {
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
              mode: _state.mode,
              normalActions: _NormalActions(
                state: _state,
                onSetBlockType: _setBlockType,
                onConvertToTask: _convertToTask,
                onInsertDivider: _insertDivider,
                onAttachImage: widget.onAttachImage,
                onAttachFile: widget.onAttachFile,
              ),
              contextualActions: _ContextualActions(
                state: _state,
                onToggleInline: _toggleInline,
                onConvertToList: _convertToList,
                onConvertToTask: _convertToTask,
                onUnindent: _unindentSelectedBlocks,
                onIndent: _indentSelectedBlocks,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setBlockType(Attribution attribution) {
    NoteEditorCommands.setBlockType(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _toggleInline(Attribution attribution) {
    NoteEditorCommands.toggleInlineAttribution(
      widget.editor,
      widget.composer,
      attribution,
    );
  }

  void _convertToList(ListItemType type) {
    NoteEditorCommands.convertToListItem(widget.editor, widget.composer, type);
  }

  void _convertToTask() {
    NoteEditorCommands.convertToTask(widget.editor, widget.composer);
  }

  void _indentSelectedBlocks() {
    NoteEditorCommands.indentSelectedBlocks(widget.editor, widget.composer);
  }

  void _unindentSelectedBlocks() {
    NoteEditorCommands.unindentSelectedBlocks(widget.editor, widget.composer);
  }

  void _insertDivider() {
    NoteEditorCommands.insertDividerAtSelection(
      widget.editor,
      widget.composer,
    );
  }
}

class _NormalActions extends StatelessWidget {
  const _NormalActions({
    required this.state,
    required this.onSetBlockType,
    required this.onConvertToTask,
    required this.onInsertDivider,
    required this.onAttachImage,
    required this.onAttachFile,
  });

  final NoteToolbarState state;
  final ValueChanged<Attribution> onSetBlockType;
  final VoidCallback onConvertToTask;
  final VoidCallback onInsertDivider;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    final blockType = state.blockType;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          svgAsset: 'assets/icons/h1_icon.svg',
          isActive: blockType == header1Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockType(header1Attribution),
          semanticLabel: 'Título 1',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h2_icon.svg',
          isActive: blockType == header2Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockType(header2Attribution),
          semanticLabel: 'Título 2',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/h3_icon.svg',
          isActive: blockType == header3Attribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockType(header3Attribution),
          semanticLabel: 'Título 3',
        ),
        ToolbarButton(
          icon: Icons.format_quote,
          isActive: blockType == blockquoteAttribution,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onSetBlockType(blockquoteAttribution),
          semanticLabel: 'Citação',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onConvertToTask,
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
    required this.onConvertToList,
    required this.onConvertToTask,
    required this.onUnindent,
    required this.onIndent,
  });

  final NoteToolbarState state;
  final ValueChanged<Attribution> onToggleInline;
  final ValueChanged<ListItemType> onConvertToList;
  final VoidCallback onConvertToTask;
  final VoidCallback onUnindent;
  final VoidCallback onIndent;

  @override
  Widget build(BuildContext context) {
    final hasText = state.hasTextSelection;
    final hasListOrTask = state.hasListOrTask;
    final activeAttributions = state.activeAttributions;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          icon: Icons.format_bold,
          isActive: activeAttributions.contains(boldAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText ? () => onToggleInline(boldAttribution) : null,
          semanticLabel: 'Negrito',
        ),
        ToolbarButton(
          icon: Icons.format_italic,
          isActive: activeAttributions.contains(italicsAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText ? () => onToggleInline(italicsAttribution) : null,
          semanticLabel: 'Itálico',
        ),
        ToolbarButton(
          icon: Icons.format_strikethrough,
          isActive: activeAttributions.contains(strikethroughAttribution),
          haptic: ToolbarHaptic.selectionChange,
          onPressed: hasText
              ? () => onToggleInline(strikethroughAttribution)
              : null,
          semanticLabel: 'Tachado',
        ),
        const ToolbarDivider(),
        ToolbarButton(
          icon: Icons.format_list_bulleted,
          isActive: state.listType == ListItemType.unordered,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onConvertToList(ListItemType.unordered),
          semanticLabel: 'Lista com marcadores',
        ),
        ToolbarButton(
          icon: Icons.format_list_numbered,
          isActive: state.listType == ListItemType.ordered,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: () => onConvertToList(ListItemType.ordered),
          semanticLabel: 'Lista numerada',
        ),
        ToolbarButton(
          svgAsset: 'assets/icons/checkbox.svg',
          isActive: state.allTasks,
          haptic: ToolbarHaptic.selectionChange,
          onPressed: onConvertToTask,
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
