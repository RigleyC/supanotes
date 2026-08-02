part of 'note_toolbar.dart';

typedef _ToolbarPopoverClose = void Function({VoidCallback? afterClose});

class _ToolbarPopoverActions {
  const _ToolbarPopoverActions({required this.close});

  final _ToolbarPopoverClose close;
}

class _ToolbarPopover extends StatefulWidget {
  const _ToolbarPopover({
    required this.triggerBuilder,
    required this.menuBuilder,
    this.onOpen,
  });

  final Widget Function(BuildContext context, bool isOpen, VoidCallback toggle)
  triggerBuilder;
  final Widget Function(BuildContext context, _ToolbarPopoverActions actions)
  menuBuilder;
  final VoidCallback? onOpen;

  @override
  State<_ToolbarPopover> createState() => _ToolbarPopoverState();
}

class _ToolbarPopoverState extends State<_ToolbarPopover>
    with TickerProviderStateMixin {
  static const _viewportMargin = 12.0;

  final _overlayController = OverlayPortalController();
  final _layerLink = LayerLink();
  final _triggerKey = GlobalKey();
  final _menuKey = GlobalKey();
  late final SingleMotionController _motion;

  FocusNode? _focusBeforeOpen;
  bool _isShowing = false;
  bool _showAbove = true;
  double _horizontalOffset = 0;
  Size _menuSize = Size.zero;
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
  void didUpdateWidget(_ToolbarPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isShowing) _scheduleMenuMeasurement();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isShowing) _scheduleMenuMeasurement();
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
    widget.onOpen?.call();
    _calculatePlacement();
    setState(() => _isShowing = true);
    _overlayController.show();
    _scheduleMenuMeasurement();
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
      afterClose?.call();
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

  void _scheduleMenuMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowing) return;
      final renderObject =
          _menuKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) return;
      if (_menuSize != renderObject.size) {
        setState(() => _menuSize = renderObject.size);
      }
      _calculatePlacement();
    });
  }

  void _calculatePlacement() {
    final renderObject =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final viewport = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top + _viewportMargin;
    final bottomPadding =
        viewport.height - MediaQuery.viewInsetsOf(context).bottom;
    final spaceAbove = topLeft.dy - topPadding;
    final spaceBelow = bottomPadding - (topLeft.dy + renderObject.size.height);

    _showAbove =
        _menuSize.height == 0 ||
        spaceAbove >= _menuSize.height ||
        spaceAbove >= spaceBelow;

    final desiredLeft =
        topLeft.dx + renderObject.size.width / 2 - _menuSize.width / 2;
    final minLeft = _viewportMargin;
    final maxLeft = viewport.width - _viewportMargin - _menuSize.width;
    final clampedLeft = desiredLeft.clamp(
      math.min(minLeft, maxLeft),
      math.max(minLeft, maxLeft),
    );
    _horizontalOffset = clampedLeft - desiredLeft;
  }

  @override
  Widget build(BuildContext context) {
    final actions = _ToolbarPopoverActions(close: _close);
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
                  child: UnconstrainedBox(
                    alignment: Alignment.topLeft,
                    child: KeyedSubtree(
                      key: _menuKey,
                      child: widget.menuBuilder(context, actions),
                    ),
                  ),
                  builder: (context, child) {
                    final progress = _motion.value.clamp(0.0, 1.0);
                    return Transform.scale(
                      alignment: _showAbove
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      scale: 0.88 + (0.12 * progress),
                      child: Opacity(opacity: progress, child: child),
                    );
                  },
                ),
              ),
            ],
          ),
          child: KeyedSubtree(
            key: _triggerKey,
            child: widget.triggerBuilder(context, _isShowing, _toggle),
          ),
        ),
      ),
    );
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

class _ToolbarFormatPopoverState extends State<_ToolbarFormatPopover> {
  DocumentSelection? _selectionForAction;

  @override
  void initState() {
    super.initState();
    _selectionForAction = widget.selection;
  }

  @override
  void didUpdateWidget(_ToolbarFormatPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      _selectionForAction = widget.selection;
    }
  }

  void _onOpen() => _selectionForAction = widget.selection;

  void _applyBlockType(Attribution attribution) {
    widget.onBlockType(attribution, _selectionForAction);
  }

  void _applyInline(Attribution attribution) {
    if (_selectionForAction?.isCollapsed ?? true) return;
    widget.onToggleInline(attribution, _selectionForAction);
  }

  @override
  Widget build(BuildContext context) {
    return _ToolbarPopover(
      onOpen: _onOpen,
      triggerBuilder: (context, isOpen, toggle) => _ToolbarButton(
        icon: Icons.text_format,
        isActive: isOpen,
        onPressed: toggle,
        semanticLabel: 'Abrir formatação',
      ),
      menuBuilder: (context, actions) => _FormattingMenu(
        key: const ValueKey('formatting-menu'),
        blockType: widget.blockType,
        hasSelection: !(_selectionForAction?.isCollapsed ?? true),
        isBold: widget.isBold,
        isItalic: widget.isItalic,
        isStrikethrough: widget.isStrikethrough,
        onBlockType: _applyBlockType,
        onToggleInline: _applyInline,
      ),
    );
  }
}

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

class _ToolbarListPopoverState extends State<_ToolbarListPopover> {
  DocumentSelection? _selectionBeforeOpen;

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

  void _onOpen() => _selectionBeforeOpen = widget.selection;

  void _select(_ListFormatOption option, _ToolbarPopoverClose close) {
    final selection = _selectionBeforeOpen;
    close(afterClose: () => widget.onSelected(option, selection));
  }

  @override
  Widget build(BuildContext context) {
    final activeOption = _activeOption;
    return _ToolbarPopover(
      onOpen: _onOpen,
      triggerBuilder: (context, isOpen, toggle) => _ToolbarButton(
        icon: _triggerIcon,
        isActive: isOpen || activeOption != null,
        onPressed: toggle,
      ),
      menuBuilder: (context, actions) => _ListFormatMenu(
        activeOption: activeOption,
        onSelected: (option) => _select(option, actions.close),
      ),
    );
  }
}
