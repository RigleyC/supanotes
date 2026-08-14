import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/progressive_fade.dart';

void main() {
  testWidgets('uses a destination-in shader over its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 200,
          height: 240,
          child: ProgressiveFade(child: ColoredBox(color: Colors.red)),
        ),
      ),
    );

    final shaderMask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    final progressiveFade = tester.widget<ProgressiveFade>(
      find.byType(ProgressiveFade),
    );
    expect(shaderMask.blendMode, BlendMode.dstIn);
    expect(progressiveFade.height, kToolbarHeight);
    expect(
      find.descendant(
        of: find.byType(ProgressiveFade),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
  });

  test('calculates the fade against the rendered bounds', () {
    final stops = ProgressiveFade.stopsForBounds(
      height: kToolbarHeight,
      boundsHeight: kToolbarHeight * 2,
    );
    expect(stops, hasLength(5));
    expect(stops[0], 0);
    expect(stops[1], 0.125);
    expect(stops[2], 0.25);
    expect(stops[3], 0.375);
    expect(stops[4], 0.5);
  });

  test('uses five progressive opacity levels across the app bar', () {
    expect(ProgressiveFade.maskColors, const [
      Color(0x33FFFFFF),
      Color(0x66FFFFFF),
      Color(0x99FFFFFF),
      Color(0xCCFFFFFF),
      Color(0xFFFFFFFF),
    ]);
  });
}
