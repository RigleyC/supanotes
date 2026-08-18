import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/note_mobile_stylesheet.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

void main() {
  group('mobileNoteStylesheet theming', () {
    testWidgets('adapts text color to light and dark theme onSurface', (
      tester,
    ) async {
      late Stylesheet lightStylesheet;
      late Stylesheet darkStylesheet;

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: AppTheme.lightTheme,
            child: Builder(
              builder: (context) {
                lightStylesheet = mobileNoteStylesheet(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: AppTheme.darkTheme,
            child: Builder(
              builder: (context) {
                darkStylesheet = mobileNoteStylesheet(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final doc = MutableDocument(
        nodes: [
          ParagraphNode(id: '1', text: AttributedText('Body text')),
          ParagraphNode(
            id: '2',
            text: AttributedText('Header 1'),
            metadata: {'blockType': header1Attribution},
          ),
          ParagraphNode(
            id: '3',
            text: AttributedText('Quote text'),
            metadata: {'blockType': blockquoteAttribution},
          ),
          TaskNode(id: '4', text: AttributedText('Task item'), isComplete: false),
        ],
      );

      final lightAllRule = lightStylesheet.rules.firstWhere(
        (r) => r.selector == BlockSelector.all,
      );
      final darkAllRule = darkStylesheet.rules.firstWhere(
        (r) => r.selector == BlockSelector.all,
      );

      final lightBodyStyles = lightAllRule.styler(doc, doc.getNodeById('1')!);
      final darkBodyStyles = darkAllRule.styler(doc, doc.getNodeById('1')!);

      expect(
        (lightBodyStyles[Styles.textStyle] as TextStyle).color,
        AppTheme.lightTheme.colorScheme.onSurface,
      );
      expect(
        (darkBodyStyles[Styles.textStyle] as TextStyle).color,
        AppTheme.darkTheme.colorScheme.onSurface,
      );
    });
  });
}
