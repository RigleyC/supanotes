import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/shared/widgets/global_sheet.dart';
import '../../helpers/haptic_test_helper.dart';

class _PushPageButton extends StatelessWidget {
  const _PushPageButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => FamilyModalSheet.of(context).pushPage(child),
      child: const Text('Abrir página interna'),
    );
  }
}

void main() {
  testWidgets('root page close button completes the sheet future', (
    tester,
  ) async {
    var closed = false;
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await showGlobalSheet<void>(
                    context: context,
                    builder: (_) => const GlobalSheetPage(
                      title: 'Página principal',
                      child: SizedBox(height: 40),
                    ),
                  );
                  closed = true;
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Página principal'), findsOneWidget);

    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
    recorder.calls.clear();
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();

    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.lightImpact',
      ),
      hasLength(1),
    );
    expect(closed, isTrue);
    expect(find.text('Página principal'), findsNothing);
  });

  testWidgets(
    'internal page close returns to root without resolving the sheet',
    (tester) async {
      var closed = false;
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    await showGlobalSheet<void>(
                      context: context,
                      builder: (_) => const GlobalSheetPage(
                        title: 'Página principal',
                        child: Center(
                          child: _PushPageButton(
                            child: GlobalSheetPage(
                              title: 'Página interna',
                              child: SizedBox(height: 40),
                            ),
                          ),
                        ),
                      ),
                    );
                    closed = true;
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Página principal'), findsOneWidget);

      await tester.tap(find.text('Abrir página interna'));
      await tester.pumpAndSettle();

      expect(find.text('Página interna'), findsOneWidget);
      expect(find.text('Página principal'), findsNothing);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Página principal'), findsOneWidget);
      expect(find.text('Página interna'), findsNothing);
      expect(recorder.count('HapticFeedbackType.lightImpact'), 2);
      expect(closed, isFalse);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(find.text('Página principal'), findsNothing);
    },
  );

  testWidgets('page header stays fixed while content scrolls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showGlobalSheet<void>(
                  context: context,
                  builder: (_) => GlobalSheetPage(
                    title: 'Página principal',
                    child: SizedBox(
                      height: 200,
                      child: ListView(
                        children: [
                          for (var i = 0; i < 100; i++)
                            SizedBox(height: 60, child: Text('Item $i')),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    final titleDy = tester.getTopLeft(find.text('Página principal')).dy;
    final closeDy = tester.getTopLeft(find.byTooltip('Fechar')).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Página principal')).dy, titleDy);
    expect(tester.getTopLeft(find.byTooltip('Fechar')).dy, closeDy);
  });
}
