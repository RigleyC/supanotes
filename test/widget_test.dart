import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/main.dart';

void main() {
  testWidgets('SupaNotesApp is const-constructible', (WidgetTester tester) async {
    // Smoke test: SupaNotesApp must be a const widget so it can be embedded
    // inside `const ProviderScope` and rebuilt cheaply on every hot reload.
    expect(const SupaNotesApp(), isA<SupaNotesApp>());
  });
}
