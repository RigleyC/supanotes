import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

import '../../helpers/haptic_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HapticTestRecorder recorder;

  setUp(() {
    recorder = HapticTestRecorder();
    recorder.install();
  });

  tearDown(() {
    recorder.dispose();
  });

  testWidgets(
    'showConfirmDialog emits a control tap for Cancelar and Confirmar',
    (tester) async {
      late Future<bool> result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = showConfirmDialog(
                    context: context,
                    title: 'Excluir nota',
                    message: 'Esta acao nao pode ser desfeita.',
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ConfirmDialogStrings.cancel));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(recorder.count('HapticFeedbackType.lightImpact'), 1);

      recorder.calls.clear();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ConfirmDialogStrings.confirm));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(recorder.count('HapticFeedbackType.lightImpact'), 1);
    },
  );
}
