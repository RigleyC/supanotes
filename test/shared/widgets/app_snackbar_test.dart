import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

void main() {
  testWidgets('AppMessenger.showSuccess exibe SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showSuccess('Salvo!');
    await tester.pumpAndSettle();

    expect(find.text('Salvo!'), findsOneWidget);
  });

  testWidgets('AppMessenger.showError exibe SnackBar com retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showError('Falhou', onRetry: () {});
    await tester.pumpAndSettle();

    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('AppMessenger.showInfo exibe SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showInfo('Informativo');
    await tester.pumpAndSettle();

    expect(find.text('Informativo'), findsOneWidget);
  });

  testWidgets('AppMessenger.showAction exibe SnackBar com acao', (tester) async {
    bool pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showAction(
      'Acao?',
      action: SnackBarAction(label: 'Sim', onPressed: () => pressed = true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acao?'), findsOneWidget);
    expect(find.text('Sim'), findsOneWidget);
  });
}
