import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

import '../../helpers/haptic_test_helper.dart';

void main() {
  late HapticTestRecorder recorder;

  setUp(() {
    recorder = HapticTestRecorder();
    recorder.install();
  });

  tearDown(() {
    recorder.dispose();
  });

  testWidgets('AppMessenger.showSuccess exibe SnackView e emite haptic', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showSuccess('Salvo!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Salvo!'), findsOneWidget);
    expect(find.byType(SnackView), findsOneWidget);
    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
  });

  testWidgets('AppMessenger.showError exibe SnackView com acao e emite haptics', (
    tester,
  ) async {
    var actionPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showError(
      'Falhou',
      action: SnackBarAction(
        label: 'Tentar novamente',
        onPressed: () => actionPressed = true,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.byType(Container), findsWidgets);
    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(actionPressed, isTrue);
    expect(recorder.count('HapticFeedbackType.lightImpact'), 2);
  });

  testWidgets('AppMessenger.showInfo exibe SnackView', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showInfo('Informativo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Informativo'), findsOneWidget);
    expect(find.byType(SnackView), findsOneWidget);
    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
  });

  testWidgets('AppMessenger.showInfo com subtitle exibe ambos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showInfo('Titulo', subtitle: 'Subtitulo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Titulo'), findsOneWidget);
    expect(find.textContaining('Subtitulo'), findsOneWidget);
    expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
  });
}
