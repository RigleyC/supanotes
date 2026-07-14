import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/advanced_regression_helpers.dart';

void main() {
  group('advanced attribution regressions', () {
    test('slices attributed visible and deleted content by id ranges', () {
      final insertAttr = _attr('user', 'alice');
      final deleteAttr = _attr('delete', 'bob');
      final manager = TwoSetAttributionManager(
        inserts: IdMap()
          ..add(advancedId(1, 1), length: 2, attributes: [insertAttr]),
        deletes: IdMap()..add(advancedId(1, 1), attributes: [deleteAttr]),
      );

      final visible = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: false,
        content: ContentAny.fromObjects(['a', 'b', 'c']),
      );
      final deleted = manager.readContent(
        client: ClientId(1),
        clock: Clock(0),
        deleted: true,
        content: ContentString('abc'),
        renderBehavior: AttributionRenderBehavior.never,
      );
      final deletedItem = advancedItem(
        Doc(gc: false),
        1,
        0,
        ContentString('abc'),
      )..markDeleted();

      expect(visible, hasLength(2));
      expect(visible.first.content.content, ['a']);
      expect(visible.first.attributes, isNull);
      expect(visible.last.content.content, ['b', 'c']);
      expect(visible.last.attributes, [insertAttr]);
      expect(deleted, hasLength(1));
      expect((deleted.single.content as ContentString).value, 'b');
      expect(deleted.single.attributes, [deleteAttr]);
      expect(manager.contentLength(deletedItem), 1);
    });

    test('filters delete attributions independently from insert filters', () {
      final accepted = _attr('state', 'accepted');
      final rejected = _attr('state', 'rejected');
      final attrs = Attributions(
        inserts: IdMap()
          ..add(advancedId(1, 0), attributes: [_attr('user', 'alice')]),
        deletes: IdMap()
          ..add(advancedId(2, 0), attributes: [accepted])
          ..add(advancedId(2, 1), attributes: [rejected]),
      );

      final filtered = attrs.filter(
        insertPredicate: (_) => false,
        deletePredicate: (attributes) => attributes.contains(rejected),
      );
      final roundTrip = Attributions.fromContentMap(filtered.toContentMap());

      expect(filtered.inserts.isEmpty, isTrue);
      expect(filtered.deletes.hasId(advancedId(2, 0)), isFalse);
      expect(filtered.deletes.hasId(advancedId(2, 1)), isTrue);
      expect(roundTrip.deletes, filtered.deletes);
    });
  });
}

ContentAttribute _attr(String name, Object? value) {
  return ContentAttribute(name, value);
}
