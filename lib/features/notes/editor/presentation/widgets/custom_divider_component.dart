import 'package:flutter/material.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_divider_art.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:super_editor/super_editor.dart';

class CustomDividerComponentBuilder implements ComponentBuilder {
  const CustomDividerComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! HorizontalRuleNode) return null;

    final dividerIndex = node.getMetadataValue('dividerIndex') as int?;

    return CustomDividerComponentViewModel(
      nodeId: node.id,
      dividerIndex: dividerIndex,
      createdAt: node.metadata[NodeMetadata.createdAt] as DateTime?,
      caretColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! CustomDividerComponentViewModel) return null;

    return CustomDividerComponent(
      componentKey: componentContext.componentKey,
      dividerIndex: componentViewModel.dividerIndex,
      selection:
          componentViewModel.selection?.nodeSelection
              as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      showCaret: componentViewModel.caret != null,
      caretColor: componentViewModel.caretColor,
      opacity: componentViewModel.opacity,
    );
  }
}

class CustomDividerComponentViewModel
    extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  CustomDividerComponentViewModel({
    required super.nodeId,
    required this.caretColor,
    this.dividerIndex,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
    this.caret,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  final int? dividerIndex;
  UpstreamDownstreamNodePosition? caret;
  Color caretColor;

  @override
  CustomDividerComponentViewModel copy() {
    return CustomDividerComponentViewModel(
      nodeId: nodeId,
      dividerIndex: dividerIndex,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      opacity: opacity,
      selection: selection,
      selectionColor: selectionColor,
      caret: caret,
      caretColor: caretColor,
    );
  }
}

class CustomDividerComponent extends StatelessWidget {
  const CustomDividerComponent({
    required this.componentKey,
    required this.caretColor,
    super.key,
    this.dividerIndex,
    this.selectionColor = AppColors.joiBlue,
    this.selection,
    this.showCaret = false,
    this.opacity = 1.0,
  });
  final GlobalKey componentKey;
  final int? dividerIndex;
  final Color selectionColor;
  final UpstreamDownstreamNodeSelection? selection;
  final Color caretColor;
  final bool showCaret;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SelectableBox(
        selection: selection,
        selectionColor: selectionColor,
        child: BoxComponent(
          key: componentKey,
          opacity: opacity,
          child: NoteDividerArt(dividerIndex: dividerIndex),
        ),
      ),
    );
  }
}
