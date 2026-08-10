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
}
