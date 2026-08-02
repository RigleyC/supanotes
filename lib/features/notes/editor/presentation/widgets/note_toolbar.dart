library;

/// Compact horizontal toolbar for the note editor.
///
/// Each button mutates the editor by dispatching a single
/// `EditRequest` — the toolbar never reads or writes the document
/// directly. The active state (bold/italic/highlights) is reflected
/// back by re-reading the composer's selection on every rebuild and
/// checking what attributions are present at the caret / selection.
///
/// The toolbar rebuilds itself independently by listening to
/// [MutableDocumentComposer.selectionNotifier], so the parent widget
/// does not need to call `setState` whenever the selection changes.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:motor/motor.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/note_editor_commands.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class NoteToolbar extends StatefulWidget {
  const NoteToolbar({
    super.key,
    required this.editor,
    required this.composer,
    this.focusNode,
    this.onAttachFile,
    this.onAttachImage,
  });

  final Editor editor;
  final MutableDocumentComposer composer;
  final FocusNode? focusNode;
  final VoidCallback? onAttachFile;
  final VoidCallback? onAttachImage;

  @override
  State<NoteToolbar> createState() => _NoteToolbarState();
}

class _NoteToolbarState extends State<NoteToolbar> {
  Editor get editor => widget.editor;
  MutableDocumentComposer get composer => widget.composer;
  VoidCallback? get onAttachFile => widget.onAttachFile;
  VoidCallback? get onAttachImage => widget.onAttachImage;
  FocusNode? get focusNode => widget.focusNode;

  DocumentSelection? _lastSelection;

  @override
  void initState() {
    super.initState();
    _lastSelection = widget.composer.selection;
    _attachListeners(widget);
  }

  @override
  void didUpdateWidget(NoteToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != widget.editor ||
        oldWidget.composer != widget.composer) {
      _detachListeners(oldWidget);
      _attachListeners(widget);
    }
  }

  @override
  void dispose() {
    _detachListeners(widget);
    super.dispose();
  }

  void _attachListeners(NoteToolbar toolbar) {
    toolbar.composer.selectionNotifier.addListener(_onEditorStateChanged);
    toolbar.editor.context.document.addListener(_onDocumentChanged);
  }

  void _detachListeners(NoteToolbar toolbar) {
    toolbar.composer.selectionNotifier.removeListener(_onEditorStateChanged);
    toolbar.editor.context.document.removeListener(_onDocumentChanged);
  }

  void _onEditorStateChanged() {
    final selection = composer.selection;
    if (selection != null && _selectionIsValid(selection)) {
      _lastSelection = selection;
    }
    if (mounted) setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) =>
      _onEditorStateChanged();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selection = composer.selection;
    final selectedNodes = _selectedNodes(selection);
    final blockType = _selectedBlockType(selectedNodes);
    final selectedListType = _selectedListType(selectedNodes);
    final isListItem = selectedNodes.any((node) => node is ListItemNode);
    final isTask =
        selectedNodes.isNotEmpty &&
        selectedNodes.every((node) => node is TaskNode);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = bottomInset > 0 ? 6.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 8,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolbarFormatPopover(
                    blockType: blockType,
                    selection: selection,
                    isBold: _selectionHasAttribution(
                      selection,
                      boldAttribution,
                    ),
                    isItalic: _selectionHasAttribution(
                      selection,
                      italicsAttribution,
                    ),
                    isStrikethrough: _selectionHasAttribution(
                      selection,
                      strikethroughAttribution,
                    ),
                    onBlockType: _onFormattingBlockType,
                    onToggleInline: _onFormattingInline,
                  ),
                  const _ToolbarDivider(),
                  _ToolbarListPopover(
                    selectedListType: selectedListType,
                    isTask: isTask,
                    selection: selection,
                    onSelected: _onListFormatSelected,
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: isListItem ? 1.0 : 0.0,
                        curve: Curves.easeInOut,
                        child: isListItem
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ToolbarButton(
                                    icon: Icons.format_indent_increase,
                                    isActive: false,
                                    onPressed: _indentListItem,
                                  ),
                                  _ToolbarButton(
                                    icon: Icons.format_indent_decrease,
                                    isActive: false,
                                    onPressed: _unindentListItem,
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const _ToolbarDivider(),
                  _ToolbarButton(
                    icon: Icons.horizontal_rule,
                    isActive: false,
                    onPressed: _insertDivider,
                  ),
                  const _ToolbarDivider(),
                  _ToolbarButton(
                    icon: Icons.image,
                    isActive: false,
                    onPressed: onAttachImage,
                  ),
                  _ToolbarButton(
                    icon: Icons.attach_file,
                    isActive: false,
                    onPressed: onAttachFile,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<DocumentNode> _selectedNodes(DocumentSelection? selection) {
    if (selection == null) return const [];
    final document = editor.context.document;
    if (document.getNodeById(selection.start.nodeId) == null ||
        document.getNodeById(selection.end.nodeId) == null) {
      return const [];
    }
    return NoteEditorCommands.selectedNodes(document, selection);
  }

  Attribution? _selectedBlockType(List<DocumentNode> nodes) {
    if (nodes.isEmpty || nodes.any((node) => node is! ParagraphNode)) {
      return null;
    }
    final blockTypes = nodes
        .cast<ParagraphNode>()
        .map((node) => node.getMetadataValue('blockType'))
        .whereType<Attribution>()
        .toSet();
    return blockTypes.length == 1 && blockTypes.length == nodes.length
        ? blockTypes.single
        : null;
  }

  ListItemType? _selectedListType(List<DocumentNode> nodes) {
    if (nodes.isEmpty || nodes.any((node) => node is! ListItemNode)) {
      return null;
    }
    final listTypes = nodes
        .cast<ListItemNode>()
        .map((node) => node.type)
        .toSet();
    return listTypes.length == 1 ? listTypes.single : null;
  }

  bool _selectionHasAttribution(
    DocumentSelection? selection,
    Attribution attribution,
  ) {
    if (selection == null || selection.isCollapsed) return false;
    var containsText = false;
    for (final node in _selectedNodes(selection).whereType<TextNode>()) {
      final startPosition = selection.start.nodeId == node.id
          ? selection.start.nodePosition
          : null;
      final endPosition = selection.end.nodeId == node.id
          ? selection.end.nodePosition
          : null;
      final start = startPosition is TextNodePosition
          ? startPosition.offset
          : 0;
      final end = endPosition is TextNodePosition
          ? endPosition.offset
          : node.text.length;
      final safeStart = start.clamp(0, node.text.length);
      final safeEnd = end.clamp(safeStart, node.text.length);
      for (var index = safeStart; index < safeEnd; index++) {
        containsText = true;
        if (!node.text.hasAttributionAt(index, attribution: attribution)) {
          return false;
        }
      }
    }
    return containsText;
  }

  void _onFormattingBlockType(
    Attribution attribution,
    DocumentSelection? selection,
  ) {
    _restoreFormattingSelection(selection);
    _setBlockType(attribution);
  }

  void _onFormattingInline(
    Attribution attribution,
    DocumentSelection? selection,
  ) {
    final actionSelection = selection ?? _lastSelection;
    if (actionSelection == null || actionSelection.isCollapsed) return;
    _restoreFormattingSelection(actionSelection);
    _toggleInline(attribution);
  }

  void _restoreFormattingSelection(DocumentSelection? selection) {
    _prepareEditorAction(selection);
  }

  DocumentSelection? _prepareEditorAction(DocumentSelection? selection) {
    final actionSelection =
        selection ?? _lastSelection ?? _selectionAtDocumentEnd();
    if (actionSelection == null || !_selectionIsValid(actionSelection)) {
      return null;
    }
    focusNode?.requestFocus();
    if (composer.selection != actionSelection) {
      composer.setSelectionWithReason(actionSelection);
    }
    return actionSelection;
  }

  DocumentSelection? _selectionAtDocumentEnd() {
    final document = editor.context.document;
    if (document.nodeCount == 0) return null;
    final lastNode = document.last;
    if (lastNode is! TextNode) return null;
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: lastNode.id,
        nodePosition: TextNodePosition(offset: lastNode.text.length),
      ),
    );
  }

  bool _selectionIsValid(DocumentSelection selection) {
    final document = editor.context.document;
    return document.getNodeById(selection.start.nodeId) != null &&
        document.getNodeById(selection.end.nodeId) != null;
  }

  void _toggleInline(Attribution attribution) {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.toggleInlineAttribution(editor, composer, attribution);
  }

  void _setBlockType(Attribution? attribution) {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.setBlockType(editor, composer, attribution);
  }

  void _convertToListItem(ListItemType type) {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.convertToListItem(editor, composer, type);
  }

  void _convertToTask() {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.convertToTask(editor, composer);
  }

  void _onListFormatSelected(
    _ListFormatOption option,
    DocumentSelection? selection,
  ) {
    if (_prepareEditorAction(selection) == null) return;
    switch (option) {
      case _ListFormatOption.bulleted:
        _convertToListItem(ListItemType.unordered);
      case _ListFormatOption.numbered:
        _convertToListItem(ListItemType.ordered);
      case _ListFormatOption.checklist:
        _convertToTask();
    }
  }

  void _indentListItem() {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.indentListItems(editor, composer);
  }

  void _unindentListItem() {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.unindentListItems(editor, composer);
  }

  void _insertDivider() {
    if (_prepareEditorAction(null) == null) return;
    HapticFeedback.selectionClick();
    NoteEditorCommands.insertDivider(editor, dividerCount: 35);
  }
}

class _ToolbarFormatPopover extends StatefulWidget {
  const _ToolbarFormatPopover({
    required this.blockType,
    required this.selection,
    required this.isBold,
    required this.isItalic,
    required this.isStrikethrough,
    required this.onBlockType,
    required this.onToggleInline,
  });

  final Attribution? blockType;
  final DocumentSelection? selection;
  final bool isBold;
  final bool isItalic;
  final bool isStrikethrough;
  final void Function(Attribution attribution, DocumentSelection? selection)
  onBlockType;
  final void Function(Attribution attribution, DocumentSelection? selection)
  onToggleInline;

  @override
  State<_ToolbarFormatPopover> createState() => _ToolbarFormatPopoverState();
}

class _ToolbarFormatPopoverState extends State<_ToolbarFormatPopover>
    with TickerProviderStateMixin {
  static const _initialMenuWidth = 176.0;
  static const _menuHeight = 232.0;
  static const _viewportMargin = 12.0;

  final _overlayController = OverlayPortalController();
  final _layerLink = LayerLink();
  final _triggerKey = GlobalKey();
  final _menuKey = GlobalKey();
  late final SingleMotionController _motion;

  FocusNode? _focusBeforeOpen;
  DocumentSelection? _selectionForAction;
  bool _isShowing = false;
  bool _showAbove = true;
  double _horizontalOffset = 0;
  double _currentMenuWidth = _initialMenuWidth;
  int _transitionId = 0;

  @override
  void initState() {
    super.initState();
    _selectionForAction = widget.selection;
    _motion = SingleMotionController(
      motion: const MaterialSpringMotion.standardSpatialFast(),
      vsync: this,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didUpdateWidget(_ToolbarFormatPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isShowing) {
      _selectionForAction = widget.selection;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _motion.dispose();
    super.dispose();
  }

  bool get _animationsDisabled =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool _handleKeyEvent(KeyEvent event) {
    if (_isShowing &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  void _toggle() {
    if (_isShowing && _motion.value > 0.5) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    _transitionId++;
    _focusBeforeOpen = FocusManager.instance.primaryFocus;
    _selectionForAction = widget.selection;
    _calculatePlacement();
    setState(() => _isShowing = true);
    _overlayController.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowing) return;
      final renderObject =
          _menuKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) return;
      if (_currentMenuWidth == renderObject.size.width) return;
      _currentMenuWidth = renderObject.size.width;
      _calculatePlacement();
      setState(() {});
    });
    _animateTo(1);
  }

  void _close() {
    if (!_isShowing) return;
    final transitionId = ++_transitionId;
    final focusNode = _focusBeforeOpen;
    _animateTo(0).then((_) {
      if (!mounted || transitionId != _transitionId) return;
      _overlayController.hide();
      setState(() => _isShowing = false);
      _focusBeforeOpen = null;
      focusNode?.requestFocus();
    });
  }

  Future<void> _animateTo(double target) async {
    if (_animationsDisabled) {
      _motion.value = target;
      return;
    }
    try {
      await _motion.animateTo(target).orCancel;
    } on TickerCanceled {
      // The controller is disposed with the toolbar.
    }
  }

  void _calculatePlacement() {
    final renderObject =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final viewport = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top + _viewportMargin;
    final bottomPadding =
        viewport.height - MediaQuery.viewInsetsOf(context).bottom;
    final spaceAbove = topLeft.dy - topPadding;
    final spaceBelow = bottomPadding - (topLeft.dy + size.height);

    _showAbove = spaceAbove >= _menuHeight || spaceAbove >= spaceBelow;
    final desiredLeft = topLeft.dx + size.width / 2 - _currentMenuWidth / 2;
    final minLeft = _viewportMargin;
    final maxLeft = viewport.width - _viewportMargin - _currentMenuWidth;
    final clampedLeft = desiredLeft.clamp(
      math.min(minLeft, maxLeft),
      math.max(minLeft, maxLeft),
    );
    _horizontalOffset = clampedLeft - desiredLeft;
  }

  void _applyBlockType(Attribution attribution) {
    widget.onBlockType(attribution, _selectionForAction ?? widget.selection);
  }

  void _applyInline(Attribution attribution) {
    if (_selectionForAction?.isCollapsed ?? true) return;
    widget.onToggleInline(attribution, _selectionForAction);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: _showAbove
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              followerAnchor: _showAbove
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              offset: Offset(_horizontalOffset, _showAbove ? -8 : 8),
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, child) {
                  final progress = _motion.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    alignment: _showAbove
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    scale: 0.88 + (0.12 * progress),
                    child: Opacity(
                      opacity: progress,
                      child: _FormattingMenu(
                        key: _menuKey,
                        blockType: widget.blockType,
                        hasSelection:
                            !(_selectionForAction?.isCollapsed ?? true),
                        isBold: widget.isBold,
                        isItalic: widget.isItalic,
                        isStrikethrough: widget.isStrikethrough,
                        onBlockType: _applyBlockType,
                        onToggleInline: _applyInline,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        child: KeyedSubtree(
          key: _triggerKey,
          child: _ToolbarButton(
            icon: Icons.text_format,
            isActive: _isShowing,
            onPressed: _toggle,
            semanticLabel: 'Abrir formatação',
          ),
        ),
      ),
    );
  }
}

class _FormattingMenu extends StatelessWidget {
  const _FormattingMenu({
    super.key,
    required this.blockType,
    required this.hasSelection,
    required this.isBold,
    required this.isItalic,
    required this.isStrikethrough,
    required this.onBlockType,
    required this.onToggleInline,
  });

  final Attribution? blockType;
  final bool hasSelection;
  final bool isBold;
  final bool isItalic;
  final bool isStrikethrough;
  final ValueChanged<Attribution> onBlockType;
  final ValueChanged<Attribution> onToggleInline;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(24);
    final highContrast = MediaQuery.highContrastOf(context);
    final surface = Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: highContrast ? 1 : 0.86),
        borderRadius: borderRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _FormattingMenuRow(
            children: [
              _ToolbarButton(
                svgAsset: 'assets/icons/h1_icon.svg',
                isActive: blockType == header1Attribution,
                onPressed: () => onBlockType(header1Attribution),
                semanticLabel: 'Título 1',
              ),
              _ToolbarButton(
                svgAsset: 'assets/icons/h2_icon.svg',
                isActive: blockType == header2Attribution,
                onPressed: () => onBlockType(header2Attribution),
                semanticLabel: 'Título 2',
              ),
              _ToolbarButton(
                svgAsset: 'assets/icons/h3_icon.svg',
                isActive: blockType == header3Attribution,
                onPressed: () => onBlockType(header3Attribution),
                semanticLabel: 'Título 3',
              ),
              _ToolbarButton(
                icon: Icons.format_quote,
                isActive: blockType == blockquoteAttribution,
                onPressed: () => onBlockType(blockquoteAttribution),
                semanticLabel: 'Citação',
              ),
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: colorScheme.outlineVariant,
              ),
              _ToolbarButton(
                icon: Icons.format_bold,
                isActive: isBold,
                onPressed: hasSelection
                    ? () => onToggleInline(boldAttribution)
                    : null,
                semanticLabel: 'Negrito',
              ),
              _ToolbarButton(
                icon: Icons.format_italic,
                isActive: isItalic,
                onPressed: hasSelection
                    ? () => onToggleInline(italicsAttribution)
                    : null,
                semanticLabel: 'Itálico',
              ),
              _ToolbarButton(
                icon: Icons.format_strikethrough,
                isActive: isStrikethrough,
                onPressed: hasSelection
                    ? () => onToggleInline(strikethroughAttribution)
                    : null,
                semanticLabel: 'Tachado',
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: 'Opções de formatação',
      child: highContrast
          ? surface
          : ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: surface,
              ),
            ),
    );
  }
}

class _FormattingMenuRow extends StatelessWidget {
  const _FormattingMenuRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: children,
    );
  }
}

enum _ListFormatOption { bulleted, numbered, checklist }

class _ToolbarListPopover extends StatefulWidget {
  const _ToolbarListPopover({
    required this.selectedListType,
    required this.isTask,
    required this.selection,
    required this.onSelected,
  });

  final ListItemType? selectedListType;
  final bool isTask;
  final DocumentSelection? selection;
  final void Function(_ListFormatOption option, DocumentSelection? selection)
  onSelected;

  @override
  State<_ToolbarListPopover> createState() => _ToolbarListPopoverState();
}

class _ToolbarListPopoverState extends State<_ToolbarListPopover>
    with TickerProviderStateMixin {
  static const _menuWidth = 160.0;
  static const _menuHeight = 176.0;
  static const _viewportMargin = 12.0;

  final _overlayController = OverlayPortalController();
  final _layerLink = LayerLink();
  final _triggerKey = GlobalKey();
  late final SingleMotionController _motion;

  FocusNode? _focusBeforeOpen;
  DocumentSelection? _selectionBeforeOpen;
  bool _isShowing = false;
  bool _showAbove = true;
  double _horizontalOffset = 0;
  double _currentMenuWidth = _menuWidth;
  double _currentMenuHeight = _menuHeight;
  int _transitionId = 0;

  @override
  void initState() {
    super.initState();
    _motion = SingleMotionController(
      motion: const MaterialSpringMotion.standardSpatialFast(),
      vsync: this,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _motion.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isShowing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowing) return;
      _calculatePlacement();
      setState(() {});
    });
  }

  bool get _animationsDisabled =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  _ListFormatOption? get _activeOption {
    if (widget.isTask) return _ListFormatOption.checklist;
    return switch (widget.selectedListType) {
      ListItemType.unordered => _ListFormatOption.bulleted,
      ListItemType.ordered => _ListFormatOption.numbered,
      null => null,
    };
  }

  IconData get _triggerIcon {
    return switch (_activeOption) {
      _ListFormatOption.checklist => Icons.check_box_outlined,
      _ListFormatOption.numbered => Icons.format_list_numbered,
      _ListFormatOption.bulleted || null => Icons.format_list_bulleted,
    };
  }

  void _toggle() {
    if (_isShowing && _motion.value > 0.5) {
      _close();
    } else {
      _open();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_isShowing &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  void _open() {
    _transitionId++;
    _focusBeforeOpen = FocusManager.instance.primaryFocus;
    _selectionBeforeOpen = widget.selection;
    _calculatePlacement();
    setState(() => _isShowing = true);
    _overlayController.show();
    _animateTo(1);
  }

  void _close({VoidCallback? afterClose}) {
    if (!_isShowing) {
      afterClose?.call();
      return;
    }

    final transitionId = ++_transitionId;
    final focusNode = _focusBeforeOpen;
    _animateTo(0).then((_) {
      if (!mounted || transitionId != _transitionId) return;
      _overlayController.hide();
      setState(() => _isShowing = false);
      _focusBeforeOpen = null;
      _selectionBeforeOpen = null;
      if (afterClose != null) {
        afterClose();
      } else {
        focusNode?.requestFocus();
      }
    });
  }

  void _select(_ListFormatOption option) {
    final focusNode = _focusBeforeOpen;
    final selection = _selectionBeforeOpen;
    _close(
      afterClose: () {
        widget.onSelected(option, selection);
        focusNode?.requestFocus();
      },
    );
  }

  Future<void> _animateTo(double target) async {
    if (_animationsDisabled) {
      _motion.value = target;
      return;
    }

    try {
      await _motion.animateTo(target).orCancel;
    } on TickerCanceled {
      // The controller is disposed with the toolbar.
    }
  }

  void _calculatePlacement() {
    final renderObject =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final viewport = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top + _viewportMargin;
    final bottomPadding =
        viewport.height - MediaQuery.viewInsetsOf(context).bottom;
    final spaceAbove = topLeft.dy - topPadding;
    final spaceBelow = bottomPadding - (topLeft.dy + size.height);

    _showAbove = spaceAbove >= _menuHeight || spaceAbove >= spaceBelow;
    final availableHeight = (_showAbove ? spaceAbove : spaceBelow) - 8;
    _currentMenuHeight = availableHeight.clamp(1.0, _menuHeight);

    _currentMenuWidth = (viewport.width - 2 * _viewportMargin).clamp(
      1.0,
      _menuWidth,
    );
    final desiredLeft = topLeft.dx + size.width / 2 - _currentMenuWidth / 2;
    final minLeft = _viewportMargin;
    final maxLeft = viewport.width - _viewportMargin - _currentMenuWidth;
    final clampedLeft = desiredLeft.clamp(
      math.min(minLeft, maxLeft),
      math.max(minLeft, maxLeft),
    );
    _horizontalOffset = clampedLeft - desiredLeft;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isShowing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isShowing) _close();
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _close,
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                targetAnchor: _showAbove
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                followerAnchor: _showAbove
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                offset: Offset(_horizontalOffset, _showAbove ? -8 : 8),
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, child) {
                    final progress = _motion.value.clamp(0.0, 1.0);
                    return Transform.scale(
                      alignment: _showAbove
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      scale: 0.88 + (0.12 * progress),
                      child: Opacity(
                        opacity: progress,
                        child: _ListFormatMenu(
                          activeOption: _activeOption,
                          width: _currentMenuWidth,
                          height: _currentMenuHeight,
                          onSelected: _select,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          child: KeyedSubtree(
            key: _triggerKey,
            child: _ToolbarButton(
              icon: _triggerIcon,
              isActive: _activeOption != null,
              onPressed: _toggle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ListFormatMenu extends StatelessWidget {
  const _ListFormatMenu({
    required this.activeOption,
    required this.width,
    required this.height,
    required this.onSelected,
  });

  final _ListFormatOption? activeOption;
  final double width;
  final double height;
  final ValueChanged<_ListFormatOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(24);
    final highContrast = MediaQuery.highContrastOf(context);

    final surface = Container(
      width: width,
      constraints: BoxConstraints(maxHeight: height),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: highContrast ? 1 : 0.82),
        borderRadius: borderRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              isActive: activeOption == _ListFormatOption.bulleted,
              onPressed: () => onSelected(_ListFormatOption.bulleted),
              semanticLabel: 'Lista com marcadores',
            ),
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              isActive: activeOption == _ListFormatOption.numbered,
              onPressed: () => onSelected(_ListFormatOption.numbered),
              semanticLabel: 'Lista numerada',
            ),
            _ToolbarButton(
              icon: Icons.check_box_outlined,
              isActive: activeOption == _ListFormatOption.checklist,
              onPressed: () => onSelected(_ListFormatOption.checklist),
              semanticLabel: 'Checklist',
            ),
          ],
        ),
      ),
    );

    final glassSurface = highContrast
        ? surface
        : ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: surface,
            ),
          );

    return Semantics(
      container: true,
      label: 'Opções de lista',
      child: glassSurface,
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    this.icon,
    this.svgAsset,
    this.semanticLabel,
    required this.isActive,
    this.onPressed,
  }) : assert(
         icon != null || svgAsset != null,
         'Provide either an icon or an svgAsset.',
       );

  final IconData? icon;
  final String? svgAsset;
  final String? semanticLabel;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton>
    with TickerProviderStateMixin {
  late final SingleMotionController _activeMotion;
  late final SingleMotionController _iconMotion;

  @override
  void initState() {
    super.initState();
    _activeMotion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: widget.isActive ? 1 : 0,
    );
    _iconMotion = SingleMotionController(
      motion: const MaterialSpringMotion.standardEffectsFast(),
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(_ToolbarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _animateTo(_activeMotion, widget.isActive ? 1 : 0);
    }
    if (oldWidget.icon != widget.icon ||
        oldWidget.svgAsset != widget.svgAsset) {
      _iconMotion.value = 0;
      _animateTo(_iconMotion, 1);
    }
  }

  @override
  void dispose() {
    _activeMotion.dispose();
    _iconMotion.dispose();
    super.dispose();
  }

  Future<void> _animateTo(
    SingleMotionController controller,
    double target,
  ) async {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      controller.value = target;
      return;
    }
    try {
      await controller.animateTo(target).orCancel;
    } on TickerCanceled {
      // The controller is disposed with the toolbar.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeProgress = _activeMotion.value.clamp(0.0, 1.0);
    final iconProgress = _iconMotion.value.clamp(0.0, 1.0);
    final inactiveColor = widget.onPressed == null
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : colorScheme.onSurface;
    final fg = Color.lerp(inactiveColor, colorScheme.primary, activeProgress)!;
    final background = colorScheme.primary.withValues(
      alpha: 0.12 * activeProgress,
    );

    final icon = widget.icon != null
        ? Icon(widget.icon, size: 26, color: fg)
        : SvgPicture.asset(
            widget.svgAsset!,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
          );

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: widget.onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Transform.scale(
            scale: 0.96 + (0.04 * activeProgress),
            child: Opacity(
              opacity: 0.7 + (0.3 * iconProgress),
              child: Transform.scale(
                scale: 0.9 + (0.1 * iconProgress),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
