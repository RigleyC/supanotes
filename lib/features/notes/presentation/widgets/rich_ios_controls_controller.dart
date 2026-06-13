import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';
import 'package:supanotes/features/notes/presentation/widgets/rich_common_editor_operations.dart';

/// A custom iOS editor controls controller that overrides native iOS popover toolbar
/// paste actions with rich-text copy and paste behaviors.
class RichSuperEditorIosControlsController extends SuperEditorIosControlsControllerWithNativePaste {
  /// Creates a [RichSuperEditorIosControlsController] with the given [editor],
  /// [documentLayoutResolver], and [operations].
  RichSuperEditorIosControlsController({
    required super.editor,
    required super.documentLayoutResolver,
    required this.operations,
  });

  /// The operations used for rich copy, paste, and cut.
  final RichCommonEditorOperations operations;

  @override
  DocumentFloatingToolbarBuilder? get toolbarBuilder => (context, mobileToolbarKey, focalPoint) {
        if (editor.composer.selection == null) {
          return const SizedBox();
        }

        return iOSSystemPopoverEditorToolbarWithFallbackBuilder(
          context,
          mobileToolbarKey,
          focalPoint,
          operations,
          SuperEditorIosControlsScope.rootOf(context),
        );
      };
}

