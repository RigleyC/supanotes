import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/note_editor_commands.dart';

import 'rich_common_editor_operations.dart';
import 'rich_ios_controls_controller.dart';
import 'rich_keyboard_actions.dart';

class EditorControls {
  final RichCommonEditorOperations richOps;
  final RichSuperEditorIosControlsController iosController;
  final SuperEditorAndroidControlsController androidController;

  EditorControls({
    required this.richOps,
    required this.iosController,
    required this.androidController,
  });

  void dispose() {
    iosController.dispose();
    androidController.dispose();
  }
}

EditorControls createEditorControls({
  required Editor editor,
  required MutableDocumentComposer composer,
  required DocumentLayout Function() documentLayoutResolver,
  required Color handleColor,
}) {
  final richOps = RichCommonEditorOperations(
    editor: editor,
    document: editor.document,
    composer: composer,
    documentLayoutResolver: documentLayoutResolver,
  );

  final iosController = RichSuperEditorIosControlsController(
    editor: editor,
    documentLayoutResolver: documentLayoutResolver,
    operations: richOps,
    handleColor: handleColor,
    toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) =>
        buildCustomSelectionToolbar(
          overlayContext,
          focalPoint,
          richOps,
          editor,
          composer,
          documentLayoutResolver,
        ),
  );

  final androidController = SuperEditorAndroidControlsController(
    controlsColor: handleColor,
    toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) =>
        buildCustomSelectionToolbar(
          overlayContext,
          focalPoint,
          richOps,
          editor,
          composer,
          documentLayoutResolver,
        ),
  );

  return EditorControls(
    richOps: richOps,
    iosController: iosController,
    androidController: androidController,
  );
}

SelectionStyles editorSelectionStyle(ColorScheme colorScheme) {
  return SelectionStyles(
    selectionColor:
        colorScheme.primary.withValues(alpha: 0.4),
  );
}

List<SuperEditorKeyboardAction> editorKeyboardActions() {
  return buildRichKeyboardActions(
    baseActions:
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android
        ? defaultImeKeyboardActions
        : defaultKeyboardActions,
  );
}

Widget buildCustomSelectionToolbar(
  BuildContext context,
  LeaderLink focalPoint,
  RichCommonEditorOperations operations,
  Editor editor,
  MutableDocumentComposer composer,
  DocumentLayout Function() documentLayoutResolver,
) {
  final selection = composer.selection;
  if (selection == null || selection.isCollapsed) return const SizedBox.shrink();

  final buttonItems = [
    ContextMenuButtonItem(
      label: 'Cortar',
      onPressed: () {
        operations.cut();
      },
      type: ContextMenuButtonType.cut,
    ),
    ContextMenuButtonItem(
      label: 'Copiar',
      onPressed: () {
        operations.copy();
        composer.clearSelection();
      },
      type: ContextMenuButtonType.copy,
    ),
    ContextMenuButtonItem(
      label: 'Colar',
      onPressed: () {
        operations.paste();
      },
      type: ContextMenuButtonType.paste,
    ),
    ContextMenuButtonItem(
      label: 'Selecionar tudo',
      onPressed: () {
        operations.selectAll();
      },
      type: ContextMenuButtonType.selectAll,
    ),
    ContextMenuButtonItem(
      label: 'Negrito',
      onPressed: () => NoteEditorCommands.toggleInlineAttribution(editor, composer, boldAttribution),
    ),
    ContextMenuButtonItem(
      label: 'Itálico',
      onPressed: () => NoteEditorCommands.toggleInlineAttribution(editor, composer, italicsAttribution),
    ),
    ContextMenuButtonItem(
      label: 'Riscado',
      onPressed: () => NoteEditorCommands.toggleInlineAttribution(editor, composer, strikethroughAttribution),
    ),
  ];

  final documentLayout = documentLayoutResolver();
  final selectionRect = documentLayout.getRectForSelection(selection.base, selection.extent);
  Offset primaryAnchor = Offset.zero;
  if (selectionRect != null) {
    primaryAnchor = documentLayout.getGlobalOffsetFromDocumentOffset(selectionRect.topCenter);
  }

  return Positioned(
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
    child: AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: primaryAnchor,
      ),
      buttonItems: buttonItems,
    ),
  );
}
