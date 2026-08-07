import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/note_desktop_stylesheet.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  testWidgets('centers list markers and checkbox on the desktop text line', (
    tester,
  ) async {
    final document = MutableDocument(
      nodes: [
        ListItemNode.unordered(
          id: 'bullet',
          text: AttributedText('Bullet item'),
        ),
        ListItemNode.ordered(
          id: 'number',
          text: AttributedText('Numbered item'),
        ),
        TaskNode(
          id: 'task',
          text: AttributedText('Task item'),
          isComplete: false,
        ),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    addTearDown(composer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: SuperEditor(
                editor: editor,
                stylesheet: desktopNoteStylesheet(
                  context,
                  documentPadding: EdgeInsets.zero,
                ),
                componentBuilders: [
                  CustomTaskComponentBuilder(),
                  ...defaultComponentBuilders,
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bulletText = find.byWidgetPredicate(
      (widget) =>
          widget is TextComponent && widget.text.toPlainText() == 'Bullet item',
    );
    final numberText = find.byWidgetPredicate(
      (widget) =>
          widget is TextComponent &&
          widget.text.toPlainText() == 'Numbered item',
    );
    final taskText = find.byWidgetPredicate(
      (widget) =>
          widget is TextComponent && widget.text.toPlainText() == 'Task item',
    );
    final bulletMarker = find.byWidgetPredicate((widget) {
      if (widget is! Container) {
        return false;
      }
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
    });
    final numberMarker = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == '1.',
    );
    final taskMarker = find.byType(AppTaskCheckbox);

    expect(bulletText, findsOneWidget);
    expect(numberText, findsOneWidget);
    expect(taskText, findsOneWidget);
    expect(bulletMarker, findsOneWidget);
    expect(numberMarker, findsOneWidget);
    expect(taskMarker, findsOneWidget);

    expect(
      tester.getRect(bulletMarker).center.dy,
      closeTo(tester.getRect(bulletText).center.dy, 0.5),
    );
    expect(
      tester.getRect(numberMarker).center.dy,
      closeTo(tester.getRect(numberText).center.dy, 0.5),
    );
    expect(
      tester.getRect(taskMarker).center.dy,
      closeTo(tester.getRect(taskText).center.dy, 0.5),
    );

    expect(
      tester.getRect(numberText).left,
      closeTo(tester.getRect(bulletText).left, 0.5),
    );
    expect(
      tester.getRect(taskText).left,
      closeTo(tester.getRect(bulletText).left, 0.5),
    );
  });
}
