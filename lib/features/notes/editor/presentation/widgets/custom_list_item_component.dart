import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

double noteEditorIndentUnit(TextStyle textStyle) {
  return (textStyle.fontSize ?? 16) * 0.60 * 4;
}

double noteEditorListIndentCalculator(TextStyle textStyle, int indent) {
  return noteEditorIndentUnit(textStyle) * (indent + 1);
}

class CustomListItemComponentBuilder extends ListItemComponentBuilder {
  const CustomListItemComponentBuilder();

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is UnorderedListItemComponentViewModel) {
      return UnorderedListItemComponent(
        componentKey: componentContext.componentKey,
        text: componentViewModel.text,
        styleBuilder: componentViewModel.textStyleBuilder,
        indent: componentViewModel.indent,
        dotStyle: componentViewModel.dotStyle,
        dotBuilder: _leftAlignedDotBuilder,
        indentCalculator: noteEditorListIndentCalculator,
        textSelection: componentViewModel.selection,
        textDirection: componentViewModel.textDirection,
        textAlignment: componentViewModel.textAlignment,
        maxLines: componentViewModel.maxLines,
        overflow: componentViewModel.overflow,
        selectionColor: componentViewModel.selectionColor,
        highlightWhenEmpty: componentViewModel.highlightWhenEmpty,
        underlines: componentViewModel.createUnderlines(),
        inlineWidgetBuilders: componentViewModel.inlineWidgetBuilders,
      );
    }

    if (componentViewModel is OrderedListItemComponentViewModel) {
      return OrderedListItemComponent(
        componentKey: componentContext.componentKey,
        indent: componentViewModel.indent,
        listIndex: componentViewModel.ordinalValue!,
        text: componentViewModel.text,
        textDirection: componentViewModel.textDirection,
        textAlignment: componentViewModel.textAlignment,
        maxLines: componentViewModel.maxLines,
        overflow: componentViewModel.overflow,
        styleBuilder: componentViewModel.textStyleBuilder,
        numeralBuilder: _leftAlignedNumeralBuilder,
        numeralStyle: componentViewModel.numeralStyle,
        indentCalculator: noteEditorListIndentCalculator,
        textSelection: componentViewModel.selection,
        selectionColor: componentViewModel.selectionColor,
        highlightWhenEmpty: componentViewModel.highlightWhenEmpty,
        underlines: componentViewModel.createUnderlines(),
        inlineWidgetBuilders: componentViewModel.inlineWidgetBuilders,
      );
    }

    return null;
  }
}

Widget _leftAlignedDotBuilder(
  BuildContext context,
  UnorderedListItemComponent component,
) {
  final attributions = component.text.getAllAttributionsAt(0).toSet();
  final textStyle = component.styleBuilder(attributions);
  final dotSize = component.dotStyle?.size ?? const Size(4, 4);

  return Align(
    key: const ValueKey('unordered-list-marker'),
    alignment: Alignment.centerLeft,
    child: Text.rich(
      TextSpan(
        text: '\u200C',
        style: textStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: dotSize.width,
              height: dotSize.height,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: component.dotStyle?.shape ?? BoxShape.circle,
                color: component.dotStyle?.color ?? textStyle.color,
              ),
            ),
          ),
        ],
      ),
      textScaler: const TextScaler.linear(1.0),
    ),
  );
}

Widget _leftAlignedNumeralBuilder(
  BuildContext context,
  OrderedListItemComponent component,
) {
  final attributions = component.text.getAllAttributionsAt(0).toSet();
  final textStyle = component
      .styleBuilder(attributions)
      .copyWith(inherit: false);

  return OverflowBox(
    maxWidth: double.infinity,
    maxHeight: double.infinity,
    child: Align(
      key: const ValueKey('ordered-list-marker'),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Text(
          '${_numeralForIndex(component.listIndex, component.numeralStyle)}.',
          textAlign: TextAlign.left,
          style: textStyle,
        ),
      ),
    ),
  );
}

String _numeralForIndex(int numeral, OrderedListNumeralStyle style) {
  return switch (style) {
    OrderedListNumeralStyle.arabic => '$numeral',
    OrderedListNumeralStyle.upperRoman => _intToRoman(numeral) ?? '$numeral',
    OrderedListNumeralStyle.lowerRoman =>
      _intToRoman(numeral)?.toLowerCase() ?? '$numeral',
    OrderedListNumeralStyle.upperAlpha => _intToAlpha(numeral),
    OrderedListNumeralStyle.lowerAlpha => _intToAlpha(numeral).toLowerCase(),
  };
}

String? _intToRoman(int number) {
  if (number < 1 || number > 3999) return null;

  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const numerals = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  var remainder = number;
  final result = StringBuffer();
  for (var index = 0; index < values.length; index++) {
    while (remainder >= values[index]) {
      result.write(numerals[index]);
      remainder -= values[index];
    }
  }
  return result.toString();
}

String _intToAlpha(int number) {
  var remainder = number;
  final result = StringBuffer();
  while (remainder > 0) {
    remainder--;
    result.writeCharCode('A'.codeUnitAt(0) + remainder % 26);
    remainder ~/= 26;
  }
  return result.toString().split('').reversed.join();
}
