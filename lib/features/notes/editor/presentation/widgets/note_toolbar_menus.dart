part of 'note_toolbar.dart';

enum _ListFormatOption { bulleted, numbered, checklist }

class _FormattingToolbarPanel extends StatelessWidget {
  const _FormattingToolbarPanel({
    required this.blockType,
    required this.selection,
    required this.activeListOption,
    required this.isListItem,
    required this.isBold,
    required this.isItalic,
    required this.isStrikethrough,
    required this.onClose,
    required this.onBlockType,
    required this.onToggleInline,
    required this.onListSelected,
    required this.onIndent,
    required this.onUnindent,
  });

  final Attribution? blockType;
  final DocumentSelection? selection;
  final _ListFormatOption? activeListOption;
  final bool isListItem;
  final bool isBold;
  final bool isItalic;
  final bool isStrikethrough;
  final VoidCallback onClose;
  final ValueChanged<Attribution> onBlockType;
  final ValueChanged<Attribution> onToggleInline;
  final ValueChanged<_ListFormatOption> onListSelected;
  final VoidCallback onIndent;
  final VoidCallback onUnindent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Painel de formatação',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Formatar',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Semantics(
                button: true,
                label: 'Fechar formatação',
                child: _ToolbarButton(
                  icon: Icons.close,
                  isActive: false,
                  onPressed: onClose,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _FormattingMenu(
              blockType: blockType,
              hasSelection: !(selection?.isCollapsed ?? true),
              isBold: isBold,
              isItalic: isItalic,
              isStrikethrough: isStrikethrough,
              onBlockType: onBlockType,
              onToggleInline: onToggleInline,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ListFormatMenu(
                activeOption: activeListOption,
                onSelected: onListSelected,
              ),
              if (isListItem) ...[
                const _ToolbarDivider(),
                _ToolbarButton(
                  icon: Icons.format_indent_increase,
                  isActive: false,
                  onPressed: onIndent,
                  semanticLabel: 'Aumentar recuo',
                ),
                _ToolbarButton(
                  icon: Icons.format_indent_decrease,
                  isActive: false,
                  onPressed: onUnindent,
                  semanticLabel: 'Diminuir recuo',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

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
          _ToolbarButton(
            svgAsset: 'assets/icons/h1_icon.svg',
            compact: true,
            isActive: blockType == header1Attribution,
            onPressed: () => onBlockType(header1Attribution),
            semanticLabel: 'Título 1',
          ),
          _ToolbarButton(
            svgAsset: 'assets/icons/h2_icon.svg',
            compact: true,
            isActive: blockType == header2Attribution,
            onPressed: () => onBlockType(header2Attribution),
            semanticLabel: 'Título 2',
          ),
          _ToolbarButton(
            svgAsset: 'assets/icons/h3_icon.svg',
            compact: true,
            isActive: blockType == header3Attribution,
            onPressed: () => onBlockType(header3Attribution),
            semanticLabel: 'Título 3',
          ),
          _ToolbarButton(
            icon: Icons.format_quote,
            compact: true,
            isActive: blockType == blockquoteAttribution,
            onPressed: () => onBlockType(blockquoteAttribution),
            semanticLabel: 'Citação',
          ),
          const _ToolbarDivider(),
          _ToolbarButton(
            icon: Icons.format_bold,
            compact: true,
            isActive: isBold,
            onPressed: hasSelection
                ? () => onToggleInline(boldAttribution)
                : null,
            semanticLabel: 'Negrito',
          ),
          _ToolbarButton(
            icon: Icons.format_italic,
            compact: true,
            isActive: isItalic,
            onPressed: hasSelection
                ? () => onToggleInline(italicsAttribution)
                : null,
            semanticLabel: 'Itálico',
          ),
          _ToolbarButton(
            icon: Icons.format_strikethrough,
            compact: true,
            isActive: isStrikethrough,
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
          _ToolbarButton(
            icon: Icons.format_list_bulleted,
            compact: true,
            isActive: activeOption == _ListFormatOption.bulleted,
            onPressed: () => onSelected(_ListFormatOption.bulleted),
            semanticLabel: 'Lista com marcadores',
          ),
          _ToolbarButton(
            icon: Icons.format_list_numbered,
            compact: true,
            isActive: activeOption == _ListFormatOption.numbered,
            onPressed: () => onSelected(_ListFormatOption.numbered),
            semanticLabel: 'Lista numerada',
          ),
          _ToolbarButton(
            svgAsset: 'assets/icons/checkbox.svg',
            compact: true,
            isActive: activeOption == _ListFormatOption.checklist,
            onPressed: () => onSelected(_ListFormatOption.checklist),
            semanticLabel: 'Checklist',
          ),
        ],
      ),
    );
  }
}
