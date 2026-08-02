part of 'note_toolbar.dart';

enum _ListFormatOption { bulleted, numbered, checklist }

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
    return Semantics(
      container: true,
      label: 'Opções de formatação',
      child: _ToolbarGlassMenuSurface(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        surfaceAlpha: 0.86,
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
            Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colorScheme.outlineVariant,
            ),
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
      child: _ToolbarGlassMenuSurface(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        surfaceAlpha: 0.82,
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
      ),
    );
  }
}

class _ToolbarGlassMenuSurface extends StatelessWidget {
  const _ToolbarGlassMenuSurface({
    required this.child,
    required this.padding,
    required this.surfaceAlpha,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double surfaceAlpha;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(24);
    final highContrast = MediaQuery.highContrastOf(context);
    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(
          alpha: highContrast ? 1 : surfaceAlpha,
        ),
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
      child: Material(type: MaterialType.transparency, child: child),
    );

    return highContrast
        ? surface
        : ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: surface,
            ),
          );
  }
}
