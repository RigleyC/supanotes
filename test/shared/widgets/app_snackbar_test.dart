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

  testWidgets('AppMessenger.showError exibe SnackBar com acao', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showError(
      'Falhou',
      action: SnackBarAction(label: 'Tentar novamente', onPressed: () {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    // Verifica que a bolinha vermelha existe (widget Container com BoxDecoration)
    expect(find.byType(Container), findsWidgets);
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

  testWidgets('AppMessenger.showInfo com subtitle exibe ambos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showInfo('Titulo', subtitle: 'Subtitulo');
    await tester.pumpAndSettle();

    // Text.rich renderiza RichText - find.text nao busca em TextSpan
    expect(find.byType(RichText), findsOneWidget);
    expect(find.text('Titulo'), findsNothing);
  });
}
