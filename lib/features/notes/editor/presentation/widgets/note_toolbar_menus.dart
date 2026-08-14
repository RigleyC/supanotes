part of 'note_formatting_panel.dart';

enum _ListFormatOption { bulleted, numbered, checklist }

class _FormattingMenu extends StatelessWidget {
  const _FormattingMenu({
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
    return Semantics(
      container: true,
      label: 'Opções de formatação',
      child: _FormattingMenuRow(
        children: [
          ToolbarButton(
            svgAsset: 'assets/icons/h1_icon.svg',
            spacious: true,
            isActive: blockType == header1Attribution,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: blockType == header1Attribution
                ? null
                : () => onBlockType(header1Attribution),
            semanticLabel: 'Título 1',
          ),
          ToolbarButton(
            svgAsset: 'assets/icons/h2_icon.svg',
            spacious: true,
            isActive: blockType == header2Attribution,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: blockType == header2Attribution
                ? null
                : () => onBlockType(header2Attribution),
            semanticLabel: 'Título 2',
          ),
          ToolbarButton(
            svgAsset: 'assets/icons/h3_icon.svg',
            spacious: true,
            isActive: blockType == header3Attribution,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: blockType == header3Attribution
                ? null
                : () => onBlockType(header3Attribution),
            semanticLabel: 'Título 3',
          ),
          ToolbarButton(
            icon: Icons.format_quote,
            spacious: true,
            isActive: blockType == blockquoteAttribution,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: blockType == blockquoteAttribution
                ? null
                : () => onBlockType(blockquoteAttribution),
            semanticLabel: 'Citação',
          ),
          const ToolbarDivider(),
          ToolbarButton(
            icon: Icons.format_bold,
            spacious: true,
            isActive: isBold,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: hasSelection
                ? () => onToggleInline(boldAttribution)
                : null,
            semanticLabel: 'Negrito',
          ),
          ToolbarButton(
            icon: Icons.format_italic,
            spacious: true,
            isActive: isItalic,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: hasSelection
                ? () => onToggleInline(italicsAttribution)
                : null,
            semanticLabel: 'Itálico',
          ),
          ToolbarButton(
            icon: Icons.format_strikethrough,
            spacious: true,
            isActive: isStrikethrough,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: hasSelection
                ? () => onToggleInline(strikethroughAttribution)
                : null,
            semanticLabel: 'Tachado',
          ),
        ],
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

class _ListFormatMenu extends StatelessWidget {
  const _ListFormatMenu({required this.activeOption, required this.onSelected});

  final _ListFormatOption? activeOption;
  final ValueChanged<_ListFormatOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Opções de lista',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToolbarButton(
            icon: Icons.format_list_bulleted,
            spacious: true,
            isActive: activeOption == _ListFormatOption.bulleted,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: () => onSelected(_ListFormatOption.bulleted),
            semanticLabel: 'Lista com marcadores',
          ),
          ToolbarButton(
            icon: Icons.format_list_numbered,
            spacious: true,
            isActive: activeOption == _ListFormatOption.numbered,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: () => onSelected(_ListFormatOption.numbered),
            semanticLabel: 'Lista numerada',
          ),
          ToolbarButton(
            svgAsset: 'assets/icons/checkbox.svg',
            spacious: true,
            isActive: activeOption == _ListFormatOption.checklist,
            haptic: ToolbarHaptic.selectionChange,
            onPressed: () => onSelected(_ListFormatOption.checklist),
            semanticLabel: 'Checklist',
          ),
        ],
      ),
    );
  }
}
