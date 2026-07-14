import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:test/test.dart';

import '../../helpers/doc_regression_helpers.dart';

void main() {
  group('document lifecycle event regressions', () {
    test('emits load once and completes the load future', () async {
      final doc = Doc();
      final loaded = <Doc>[];
      doc.onLoad.add(loaded.add);

      final firstFuture = doc.load();
      final secondFuture = doc.load();
      await firstFuture;

      expect(firstFuture, same(secondFuture));
      expect(loaded, [doc]);
      expect(doc.isLoaded, isTrue);
      expect(doc.shouldLoad, isTrue);
    });

    test('emits sync transitions without duplicate same-state events',
        () async {
      final doc = Doc();
      final events = <DocSyncEvent>[];
      doc.onSync.add(events.add);

      doc
        ..setSynced(true)
        ..setSynced(true)
        ..setSynced(false)
        ..setSynced(false)
        ..setSynced(true);
      await doc.whenSynced;

      expect(events.map((event) => event.synced).toList(), [
        true,
        false,
        true,
      ]);
      expect(events.every((event) => identical(event.doc, doc)), isTrue);
      expect(doc.isSynced, isTrue);
    });

    test('emits subdocument add, load, and remove events from parent doc',
        () async {
      final doc = Doc();
      final child = Subdocument(guid: 'child', shouldLoad: true);
      final events = <SubdocsEvent>[];
      doc.onSubdocs.add(events.add);

      addSubdocumentInTransaction(doc, child);
      await child.load();
      removeSubdocumentInTransaction(doc, child);

      expect(events, hasLength(3));
      expect(events[0].added, {child});
      expect(events[0].loaded, {child});
      expect(events[0].removed, isEmpty);
      expect(events[1].added, isEmpty);
      expect(events[1].loaded, {child});
      expect(events[1].transaction.origin, same(child));
      expect(events[2].removed, {child});
      expect(doc.getSubdocs(), isEmpty);
      expect(doc.getSubdocGuids(), isEmpty);
    });
  });
}
