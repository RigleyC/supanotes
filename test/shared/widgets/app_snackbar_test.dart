import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

void main() {
  testWidgets('AppMessenger.showSuccess exibe SnackView', (tester) async {
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
  });

  testWidgets('AppMessenger.showError exibe SnackView com acao', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    AppMessenger.showError(
      'Falhou',
      action: SnackBarAction(label: 'Tentar novamente', onPressed: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.byType(Container), findsWidgets);
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
  });
}
