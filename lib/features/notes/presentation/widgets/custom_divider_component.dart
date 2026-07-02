import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      createdAt: node.metadata[NodeMetadata.createdAt],
      selectionColor: const Color(0x00000000),
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
    this.dividerIndex,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
    this.caret,
    required this.caretColor,
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
    super.key,
    required this.componentKey,
    this.dividerIndex,
    this.selectionColor = Colors.blue,
    this.selection,
    required this.caretColor,
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

  // Number of available divider SVG assets
  static const int _dividerCount = 35;

  @override
  Widget build(BuildContext context) {
    final safeIndex = (dividerIndex ?? 1).clamp(1, _dividerCount);
    final padIndex = safeIndex.toString().padLeft(2, '0');
    final assetPath = 'assets/dividers/divider_$padIndex.svg';

    return IgnorePointer(
      child: SelectableBox(
        selection: selection,
        selectionColor: selectionColor,
        child: BoxComponent(
          key: componentKey,
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SizedBox(
              height: 24,
              width: double.infinity,
              child: SvgPicture.asset(assetPath, fit: BoxFit.fitWidth),
            ),
          ),
        ),
      ),
    );
  }
}
