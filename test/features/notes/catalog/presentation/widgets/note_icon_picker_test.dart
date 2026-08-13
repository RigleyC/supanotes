import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';

void main() {
  testWidgets('catalog picker exposes 48px color and icon hit targets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCatalogIconPickerPage(
            current: null,
            onSelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    final colorTarget = find.bySemanticsLabel('Cor red');
    final iconTarget = find.bySemanticsLabel('Carteira');

    expect(colorTarget, findsOneWidget);
    expect(iconTarget, findsOneWidget);
    expect(tester.getSize(colorTarget), const Size(48, 48));
    expect(tester.getSize(iconTarget).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(iconTarget).height, greaterThanOrEqualTo(48));
  });

  testWidgets('emoji picker keeps title and search fixed while grid scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEmojiPickerPage(onSelected: (_) async {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Escolher emoji'), findsOneWidget);
    expect(find.text('Buscar emojis'), findsOneWidget);

    final titleDy = tester.getTopLeft(find.text('Escolher emoji')).dy;
    final searchDy = tester.getTopLeft(find.text('Buscar emojis')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Escolher emoji')).dy, titleDy);
    expect(tester.getTopLeft(find.text('Buscar emojis')).dy, searchDy);
  });

  testWidgets(
    'catalog picker keeps search and color controls fixed while grid scrolls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCatalogIconPickerPage(
              current: null,
              onSelected: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Escolher ícone'), findsOneWidget);
      expect(find.text('Buscar ícones'), findsOneWidget);
      expect(find.bySemanticsLabel('Cor red'), findsOneWidget);

      final searchDy = tester.getTopLeft(find.text('Buscar ícones')).dy;
      final colorDy = tester.getTopLeft(find.bySemanticsLabel('Cor red')).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Buscar ícones')).dy, searchDy);
      expect(tester.getTopLeft(find.bySemanticsLabel('Cor red')).dy, colorDy);
    },
  );
}
