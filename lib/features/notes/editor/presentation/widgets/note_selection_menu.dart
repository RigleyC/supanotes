import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';

/// Copy, cut, paste and select all for a note.
///
/// AppFlowy's clipboard only puts plain text on the system clipboard, so
/// formatting and block types would be lost between copy and paste. The
/// copied blocks are kept here next to the plain text written to the system
/// clipboard; pasting that same text puts the blocks back with their
/// formatting. Anything else on the clipboard is pasted as plain text.
abstract final class NoteClipboard {
  static String? _text;
  static List<Node>? _nodes;

  /// Copies the selection, keeping its formatting for pastes in the app.
  static Future<void> copy(EditorState editorState) async {
    final selection = editorState.selection?.normalized;
    if (selection == null || selection.isCollapsed) return;
    final text = editorState.getTextInSelection(selection).join('\n');
    _nodes = [
      for (final node in editorState.getSelectedNodes(selection: selection))
        _withoutIdentity(node),
    ];
    _text = text;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Copies the selection, then deletes it.
  static Future<void> cut(EditorState editorState) async {
    final selection = editorState.selection?.normalized;
    if (selection == null || selection.isCollapsed) return;
    await copy(editorState);
    await editorState.deleteSelection(selection);
  }

  /// Pastes at the selection: blocks copied in the app with their
  /// formatting, anything else as plain text.
  static Future<void> paste(EditorState editorState) async {
    if (editorState.selection == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final nodes = _nodes;
    if (nodes != null && nodes.isNotEmpty && text == _text) {
      final copies = [for (final node in nodes) node.deepCopy()];
      if (copies.length == 1) {
        await editorState.pasteSingleLineNode(copies.single);
      } else {
        await editorState.pasteMultiLineNodes(copies);
      }
      return;
    }
    final lines = text.replaceAll('\r', '').split('\n');
    final paragraphs = [for (final line in lines) paragraphNode(text: line)];
    if (paragraphs.length == 1) {
      await editorState.pasteSingleLineNode(paragraphs.single);
    } else {
      await editorState.pasteMultiLineNodes(paragraphs);
    }
  }

  /// Selects the whole note.
  static void selectAll(EditorState editorState) {
    var last = editorState.document.root.children.lastOrNull;
    if (last == null) return;
    while (last!.children.isNotEmpty) {
      last = last.children.last;
    }
    editorState.updateSelectionWithReason(
      Selection(
        start: Position(path: [0]),
        // Blocks without text (dividers, attachments) end at offset 1.
        end: Position(path: last.path, offset: last.delta?.length ?? 1),
      ),
      reason: SelectionUpdateReason.selectAll,
    );
  }

  /// A pasted block is a new block: it must not take the copied block's id.
  static Node _withoutIdentity(Node node) {
    final attributes = Map<String, dynamic>.from(node.attributes)
      ..remove(NoteNodeKeys.blockId);
    return Node(
      type: node.type,
      attributes: attributes,
      children: [for (final child in node.children) _withoutIdentity(child)],
    );
  }

  @visibleForTesting
  static void reset() {
    _text = null;
    _nodes = null;
  }
}

/// Shows the edit menu (copy, cut, paste, select all) for the selection.
///
/// On iOS it is the system's own edit menu, drawn by iOS (with its current
/// look, e.g. the glass menu of iOS 26), whose buttons run the note's
/// copy/paste so formatting is kept. Elsewhere, or when iOS cannot show it,
/// Flutter's adaptive text selection toolbar is used.
///
/// The menu appears when a selection gesture ends, or when the caret is
/// tapped again; it hides while a handle is dragged, when typing, scrolling
/// or when editing stops.
class NoteSelectionMenu extends StatefulWidget {
  const NoteSelectionMenu({
    required this.editorState,
    required this.editing,
    required this.child,
    this.scrollController,
    this.enabled = true,
    super.key,
  });

  final EditorState editorState;

  /// Whether the user is editing; the menu only shows while this is true.
  final ValueListenable<bool> editing;
  final EditorScrollController? scrollController;

  /// False for read-only notes.
  final bool enabled;
  final Widget child;

  @override
  State<NoteSelectionMenu> createState() => NoteSelectionMenuState();
}

@visibleForTesting
class NoteSelectionMenuState extends State<NoteSelectionMenu> {
  SystemContextMenuController? _systemMenu;
  OverlayEntry? _flutterMenu;
  Selection? _previousCaret;
  Timer? _showTimer;
  bool _visible = false;
  bool _systemMenuShown = false;

  /// The key and values AppFlowy uses to mark a handle being dragged.
  static const _dragModeKey = 'selection_drag_mode';
  static const _handleDragModes = {
    'leftSelectionHandle',
    'rightSelectionHandle',
  };

  /// Whether a menu is showing (for tests).
  @visibleForTesting
  bool get isVisible => _visible;

  EditorState get _editorState => widget.editorState;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(NoteSelectionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState ||
        oldWidget.editing != widget.editing ||
        oldWidget.scrollController != widget.scrollController) {
      _unlisten(oldWidget);
      _listen();
    }
    if (!widget.enabled) _hide();
  }

  @override
  void dispose() {
    _unlisten(widget);
    _hide();
    _systemMenu?.dispose();
    super.dispose();
  }

  void _listen() {
    _editorState.selectionNotifier.addListener(_onSelectionChanged);
    widget.editing.addListener(_onEditingChanged);
    widget.scrollController?.offsetNotifier.addListener(_hide);
  }

  void _unlisten(NoteSelectionMenu widget) {
    widget.editorState.selectionNotifier.removeListener(_onSelectionChanged);
    widget.editing.removeListener(_onEditingChanged);
    widget.scrollController?.offsetNotifier.removeListener(_hide);
  }

  void _onEditingChanged() {
    if (!widget.editing.value) _hide();
  }

  void _onSelectionChanged() {
    final selection = _editorState.selection;
    if (selection == null ||
        _editorState.selectionType == SelectionType.block) {
      _previousCaret = null;
      _hide();
      return;
    }
    final extraInfo = _editorState.selectionExtraInfo;
    if (selection.isCollapsed) {
      // Typing or moving the caret hides the menu; tapping the caret where it
      // already is shows it (paste, select all).
      final tappedAgain =
          _previousCaret == selection &&
          _editorState.selectionUpdateReason == SelectionUpdateReason.uiEvent &&
          extraInfo?[selectionExtraInfoDisableFloatingToolbar] != true;
      _hide();
      if (tappedAgain) _scheduleShow();
      _previousCaret = selection;
      return;
    }
    _previousCaret = null;
    _hide();
    // AppFlowy tags selection updates made while a handle is dragged.
    final dragMode = extraInfo?[_dragModeKey];
    final dragging =
        (dragMode is Enum && _handleDragModes.contains(dragMode.name)) ||
        extraInfo?[selectionExtraInfoDisableFloatingToolbar] == true;
    if (!dragging) _scheduleShow();
  }

  /// Shows after the frame, once the selection's layout is up to date.
  void _scheduleShow() {
    _showTimer?.cancel();
    _showTimer = Timer(Duration.zero, () {
      if (mounted) show();
    });
  }

  /// Shows the menu for the current selection, if it can.
  @visibleForTesting
  void show() {
    if (!widget.enabled || !widget.editing.value) return;
    final selection = _editorState.selection;
    if (selection == null) return;
    final rects = _editorState.selectionRects();
    if (rects.isEmpty) return;
    final target = rects.reduce((a, b) => a.expandToInclude(b));
    final hasText = !selection.isCollapsed;

    if (SystemContextMenu.isSupported(context)) {
      _showSystemMenu(target, selection, hasText: hasText);
    } else {
      _showFlutterMenu(target, hasText: hasText);
    }
    _visible = true;
  }

  void _showSystemMenu(
    Rect target,
    Selection selection, {
    required bool hasText,
  }) {
    final menu = _systemMenu ??= SystemContextMenuController(
      onSystemHide: () {
        _visible = false;
        _systemMenuShown = false;
      },
    );
    _systemMenuShown = true;
    unawaited(
      menu.showWithItems(target, [
        if (hasText) ...[
          IOSSystemContextMenuItemDataCustom(
            title: 'Recortar',
            onPressed: () => _run(NoteClipboard.cut),
          ),
          IOSSystemContextMenuItemDataCustom(
            title: 'Copiar',
            onPressed: () => _run(NoteClipboard.copy),
          ),
        ],
        IOSSystemContextMenuItemDataCustom(
          title: 'Colar',
          onPressed: () => _run(NoteClipboard.paste),
        ),
        IOSSystemContextMenuItemDataCustom(
          title: 'Selecionar tudo',
          onPressed: () => _run((editorState) async {
            NoteClipboard.selectAll(editorState);
          }),
        ),
        // iOS looks these up in the text it holds for the current block, so
        // they are only offered for a selection within one block.
        if (hasText && selection.isSingle) ...[
          const IOSSystemContextMenuItemDataLookUp(title: 'Pesquisar'),
          const IOSSystemContextMenuItemDataSearchWeb(
            title: 'Buscar na web',
          ),
          const IOSSystemContextMenuItemDataShare(title: 'Compartilhar...'),
        ],
      ]),
    );
  }

  void _showFlutterMenu(Rect target, {required bool hasText}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final items = [
      if (hasText) ...[
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () => _run(NoteClipboard.cut),
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => _run(NoteClipboard.copy),
        ),
      ],
      ContextMenuButtonItem(
        type: ContextMenuButtonType.paste,
        onPressed: () => _run(NoteClipboard.paste),
      ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () => _run((editorState) async {
          NoteClipboard.selectAll(editorState);
        }),
      ),
    ];
    _flutterMenu = OverlayEntry(
      builder: (context) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: Offset(target.center.dx, target.top),
          secondaryAnchor: Offset(target.center.dx, target.bottom),
        ),
        buttonItems: items,
      ),
    );
    overlay.insert(_flutterMenu!);
  }

  void _run(Future<void> Function(EditorState editorState) action) {
    _hide();
    unawaited(action(_editorState));
  }

  void _hide() {
    _showTimer?.cancel();
    _showTimer = null;
    _flutterMenu?.remove();
    _flutterMenu?.dispose();
    _flutterMenu = null;
    if (_systemMenuShown) unawaited(_systemMenu?.hide());
    _systemMenuShown = false;
    _visible = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
