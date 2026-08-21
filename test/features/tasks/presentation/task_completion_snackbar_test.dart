import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('minimal snackbar dismiss test', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Concluída!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump(); // start entry animation
    await tester.pump(
      const Duration(milliseconds: 750),
    ); // let entry animation finish
    expect(find.textContaining('Concluída!'), findsOneWidget);

    await tester.pump(
      const Duration(seconds: 2),
    ); // wait for duration, starts exit animation
    await tester.pump(); // process state change
    await tester.pump(
      const Duration(milliseconds: 750),
    ); // let exit animation finish
    expect(find.textContaining('Concluída!'), findsNothing);
  });
}
