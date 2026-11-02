import 'package:block_editor/src/rendering/block_selection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  );
}

Finder findHighlightPaint() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is SelectionHighlightPainter,
  );
}

void main() {
  group('BlockSelectionOverlay — coverage', () {
    testWidgets('returns child directly when isCovered is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(
            isCovered: false,
            child: Text('block content'),
          ),
        ),
      );
      expect(findHighlightPaint(), findsNothing);
      expect(find.text('block content'), findsOneWidget);
    });

    testWidgets('wraps child in CustomPaint when isCovered is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(
            isCovered: true,
            child: Text('block content'),
          ),
        ),
      );
      expect(findHighlightPaint(), findsOneWidget);
      expect(find.text('block content'), findsOneWidget);
    });
  });

  group('BlockSelectionOverlay — highlight color', () {
    testWidgets('uses default highlight color when none supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(isCovered: true, child: Text('content')),
        ),
      );
      final customPaint = tester.widget<CustomPaint>(findHighlightPaint());
      final painter = customPaint.painter! as SelectionHighlightPainter;
      expect(painter.color, const Color(0x443399FF));
    });

    testWidgets('uses supplied highlight color', (tester) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(
            isCovered: true,
            highlightColor: Color(0x44FF0000),
            child: Text('content'),
          ),
        ),
      );
      final customPaint = tester.widget<CustomPaint>(findHighlightPaint());
      final painter = customPaint.painter! as SelectionHighlightPainter;
      expect(painter.color, const Color(0x44FF0000));
    });
  });

  group('BlockSelectionOverlay — child is always rendered', () {
    testWidgets('child renders when covered', (tester) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(isCovered: true, child: Text('visible')),
        ),
      );
      expect(find.text('visible'), findsOneWidget);
    });

    testWidgets('child renders when not covered', (tester) async {
      await tester.pumpWidget(
        wrap(
          const BlockSelectionOverlay(isCovered: false, child: Text('visible')),
        ),
      );
      expect(find.text('visible'), findsOneWidget);
    });
  });

  group('SelectionHighlightPainter — shouldRepaint', () {
    test('returns false when color is unchanged', () {
      const painter = SelectionHighlightPainter(color: Color(0x443399FF));
      expect(
        painter.shouldRepaint(
          const SelectionHighlightPainter(color: Color(0x443399FF)),
        ),
        isFalse,
      );
    });

    test('returns true when color changes', () {
      const painter = SelectionHighlightPainter(color: Color(0x443399FF));
      expect(
        painter.shouldRepaint(
          const SelectionHighlightPainter(color: Color(0x44FF0000)),
        ),
        isTrue,
      );
    });
  });
}
