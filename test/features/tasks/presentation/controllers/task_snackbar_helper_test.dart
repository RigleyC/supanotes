import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets('TaskSnackBarHelper.completeTaskWithFeedback shows snackbar without next due date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    bool completed = false;
    bool undone = false;

    await TaskSnackBarHelper.completeTaskWithFeedback(
      onComplete: () async {
        completed = true;
        return null;
      },
      onUndo: () {
        undone = true;
      },
    );

    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(find.text('Tarefa concluída!'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    expect(undone, isTrue);
  });

  testWidgets('TaskSnackBarHelper.completeTaskWithFeedback shows snackbar with next due date', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppMessenger.key,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    final nextDue = DateTime(2030, 3, 15);

    await TaskSnackBarHelper.completeTaskWithFeedback(
      onComplete: () async => nextDue,
      onUndo: () {},
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Tarefa concluída!  Próx. em:'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
  });
}
