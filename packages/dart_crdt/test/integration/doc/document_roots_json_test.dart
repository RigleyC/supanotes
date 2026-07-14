import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

void main() {
  group('document root and JSON regressions', () {
    test('uses the empty root id for the default root only', () {
      final doc = Doc();
      final emptyRootId = '';
      final implicitRoot = doc.get();
      final explicitRoot = doc.get(emptyRootId);

      expect(explicitRoot, same(implicitRoot));
      expect(implicitRoot.name, isEmpty);
      expect(implicitRoot.kind, SharedTypeKind.map);
      expect(implicitRoot.isRoot, isTrue);
      expect(() => doc.itemParentForKey(''), throwsArgumentError);
    });

    test('renders stable defensive JSON for every registered root', () {
      final doc = Doc();
      doc.get();
      doc.get('items', SharedTypeKind.array);
      doc.get('body', SharedTypeKind.text);

      final json = doc.toJson();

      expect(json.keys.toList(), ['', 'items', 'body']);
      expect(json, {
        '': {'kind': 'map', 'name': ''},
        'items': {'kind': 'array', 'name': 'items'},
        'body': {'kind': 'text', 'name': 'body'},
      });
      expect(
        () => json['other'] = const <String, Object?>{},
        throwsUnsupportedError,
      );
    });
  });
}
