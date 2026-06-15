import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';

void main() {
  group('UserSettings', () {
    test('fromJson parses correctly', () {
      final json = {
        'timezone': 'America/Sao_Paulo',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-06-01T00:00:00.000Z',
      };
      final settings = UserSettings.fromJson(json);
      expect(settings.timezone, 'America/Sao_Paulo');
      expect(settings.createdAt, DateTime.utc(2025, 1, 1).toLocal());
    });
  });

  group('Soul', () {
    test('fromJson parses correctly', () {
      final json = {'personality': 'Be helpful.'};
      final soul = Soul.fromJson(json);
      expect(soul.personality, 'Be helpful.');
    });

    test('fromJson defaults to empty string', () {
      final json = <String, dynamic>{};
      final soul = Soul.fromJson(json);
      expect(soul.personality, '');
    });
  });

  group('UserContext', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'c-1',
        'slug': 'work',
        'name': 'Trabalho',
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-06-01T00:00:00.000Z',
      };
      final ctx = UserContext.fromJson(json);
      expect(ctx.id, 'c-1');
      expect(ctx.slug, 'work');
      expect(ctx.name, 'Trabalho');
    });
  });
}
