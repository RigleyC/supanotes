import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

void main() {
  group('SearchResultModel', () {
    test('fromJson parses correctly', () {
      final json = {
        'ID': 'n-1',
        'Title': 'My Note',
        'Excerpt': 'Some content here...',
        'Score': 0.85,
      };
      final model = SearchResultModel.fromJson(json);
      expect(model.id, 'n-1');
      expect(model.title, 'My Note');
      expect(model.excerpt, 'Some content here...');
      expect(model.score, 0.85);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};
      final model = SearchResultModel.fromJson(json);
      expect(model.id, '');
      expect(model.title, '');
      expect(model.excerpt, '');
      expect(model.score, 0.0);
    });

    test('fromJson handles Score as int', () {
      final json = {
        'ID': 'n-2',
        'Title': 'Test',
        'Excerpt': 'Excerpt',
        'Score': 42,
      };
      final model = SearchResultModel.fromJson(json);
      expect(model.score, 42.0);
    });

    test('fromJson handles Score as null', () {
      final json = {
        'ID': 'n-3',
        'Title': 'Test',
        'Excerpt': 'Excerpt',
        'Score': null,
      };
      final model = SearchResultModel.fromJson(json);
      expect(model.score, 0.0);
    });
  });
}
