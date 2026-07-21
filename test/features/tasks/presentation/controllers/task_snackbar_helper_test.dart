import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets('TaskSnackBarHelper.completeTaskWithFeedback shows snackbar without next due date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    bool completed = false;

    await TaskSnackBarHelper.completeTaskWithFeedback(
      onComplete: () async {
        completed = true;
        return (nextDue: null, previousDue: null, previousHasTime: false, scheduledAt: null);
      },
      onUndo: (_, __, ___) {},
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(find.textContaining('Concluída!'), findsOneWidget);
    expect(find.textContaining('Desfazer'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('TaskSnackBarHelper.completeTaskWithFeedback shows snackbar with next due date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        builder: (context, child) => SnackOverlay(child: child!),
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final nextDue = DateTime(2030, 3, 15);

    await TaskSnackBarHelper.completeTaskWithFeedback(
      onComplete: () async => (nextDue: nextDue, previousDue: null, previousHasTime: false, scheduledAt: null),
      onUndo: (_, __, ___) {},
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Concluída!'), findsOneWidget);
    expect(find.textContaining('Desfazer'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });
}
