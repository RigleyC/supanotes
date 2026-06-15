import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/presentation/widgets/search_bar.dart';

void main() {
  testWidgets('renders with hint text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchInputBar(
          onQueryChanged: (_) {},
          hintText: 'Buscar notas',
          autofocus: false,
        ),
      ),
    ));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Buscar notas'), findsOneWidget);
  });

  testWidgets('shows clear button when text is entered', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchInputBar(
          onQueryChanged: (_) {},
          hintText: 'Buscar notas',
          autofocus: false,
        ),
      ),
    ));
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('clear button hides when text is cleared via clear button',
      (tester) async {
    String emitted = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchInputBar(
          onQueryChanged: (v) => emitted = v,
          hintText: 'Buscar notas',
          autofocus: false,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(emitted, '');
  });

  testWidgets('debounce delays the callback', (tester) async {
    String emitted = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchInputBar(
          onQueryChanged: (v) => emitted = v,
          debounce: const Duration(milliseconds: 50),
          autofocus: false,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'test');
    expect(emitted, '');

    await tester.pump(const Duration(milliseconds: 30));
    expect(emitted, '');

    await tester.pump(const Duration(milliseconds: 30));
    expect(emitted, 'test');
  });

  testWidgets('accepts initial query', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchInputBar(
          onQueryChanged: (_) {},
          initialQuery: 'prefilled',
          autofocus: false,
        ),
      ),
    ));
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, 'prefilled');
  });
}
