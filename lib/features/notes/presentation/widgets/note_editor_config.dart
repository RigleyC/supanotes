import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

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
  );

  final androidController = SuperEditorAndroidControlsController(
    controlsColor: handleColor,
    toolbarBuilder: (overlayContext, mobileToolbarKey, focalPoint) =>
        defaultAndroidEditorToolbarBuilder(
          overlayContext,
          mobileToolbarKey,
          richOps,
          SuperEditorAndroidControlsScope.rootOf(overlayContext),
          composer.selectionNotifier,
          focalPoint,
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

