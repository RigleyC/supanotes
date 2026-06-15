import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

void main() {
  group('slugifyContextName', () {
    test('lowercases and replaces spaces', () {
      expect(slugifyContextName('Trabalho'), 'trabalho');
      expect(slugifyContextName('Meu Projeto'), 'meu-projeto');
    });

    test('removes non-alphanumeric characters', () {
      expect(slugifyContextName('Notas @2025!'), 'notas-2025');
    });

    test('strips leading and trailing hyphens', () {
      expect(slugifyContextName('-teste-'), 'teste');
    });

    test('falls back to "context" when empty', () {
      expect(slugifyContextName(''), 'context');
      expect(slugifyContextName('   '), 'context');
    });

    test('truncates at 50 characters', () {
      final long = 'a' * 100;
      final result = slugifyContextName(long);
      expect(result.length, 50);
    });
  });
}
