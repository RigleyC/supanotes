/// Diff and snapshot attribution managers.
library;

import '../content/content.dart';
import '../doc/doc.dart';
import '../events/event_handler.dart';
import '../metadata/content_attribute.dart';
import '../metadata/content_ids.dart';
import '../metadata/id_map.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../snapshot/snapshot.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../sync/apply_update.dart';
import '../sync/state_update.dart';
import '../sync/update_content_ids.dart';
import '../undo/undo_manager.dart';
import 'attribution_manager.dart';

part 'diff_snapshot_attribution_event.dart';

/// Attribution manager that describes content differences between documents.
final class DiffAttributionManager implements AttributionManager {
  /// Creates a diff attribution manager.
  DiffAttributionManager(
    this.previousDoc,
    this.nextDoc, {
    Attributions? attributions,
  }) : _attributions = attributions ?? Attributions.empty() {
    _delegate = _createDelegate();
    _subscription = nextDoc.afterTransaction.add(_afterTransaction);
    _previousUpdateSubscription = previousDoc.update.add(_syncPreviousUpdate);
    _nextUpdateSubscription = nextDoc.update.add(_syncNextUpdate);
  }

  /// Previous document used as the comparison base.
  final Doc previousDoc;

  /// Next document used as the comparison target.
  final Doc nextDoc;

  final Attributions _attributions;
  final EventHandler<AttributionChangeEvent> _change =
      EventHandler<AttributionChangeEvent>();
  late TwoSetAttributionManager _delegate;
  late final EventSubscription _subscription;
  late final EventSubscription _previousUpdateSubscription;
  late final EventSubscription _nextUpdateSubscription;

  /// Whether target-document changes remain suggestions instead of syncing.
  bool suggestionMode = true;

  /// Optional origins allowed to sync when [suggestionMode] is disabled.
  Set<Object?>? suggestionOrigins;

  /// Emits after [nextDoc] transactions change attribution ranges.
  EventHandler<AttributionChangeEvent> get change => _change;

  /// Stops observing [nextDoc].
  void destroy() {
    _subscription.cancel();
    _previousUpdateSubscription.cancel();
    _nextUpdateSubscription.cancel();
    _change.clear();
  }

  /// Current suggested insert/delete ids; deleted content requires `gc: false`.
  ContentIds get suggestedChanges {
    return ContentIds(
      inserts: _documentIds(nextDoc).diff(_documentIds(previousDoc)),
      deletes: _deleteIds(nextDoc).diff(_deleteIds(previousDoc)),
    );
  }

  /// Applies all suggested changes to [previousDoc] using update sync.
  void acceptAllChanges() {
    applyUpdate(previousDoc, encodeStateAsUpdate(nextDoc), origin: this);
  }

  /// Reverts all suggested changes from [nextDoc] unless GC removed content.
  void rejectAllChanges() {
    undoContentIds(nextDoc, suggestedChanges);
  }

  /// Applies suggested changes in the inclusive id range [start] to [end].
  void acceptChanges(Id start, [Id? end]) {
    final selected = _selectedChanges(start, end);
    if (selected.isEmpty) {
      return;
    }
    applyUpdate(
      previousDoc,
      intersectUpdateWithContentIds(encodeStateAsUpdate(nextDoc), selected),
      origin: this,
    );
  }

  /// Reverts suggested changes in the inclusive id range [start] to [end].
  void rejectChanges(Id start, [Id? end]) {
    final selected = _selectedChanges(start, end);
    if (selected.isEmpty) {
      return;
    }
    undoContentIds(nextDoc, selected);
  }

  @override
  List<AttributedContent> readContent({
    required ClientId client,
    required Clock clock,
    required bool deleted,
    required AbstractContent content,
    AttributionRenderBehavior renderBehavior =
        AttributionRenderBehavior.whenVisibleOrAttributed,
  }) {
    return _delegate.readContent(
      client: client,
      clock: clock,
      deleted: deleted,
      content: content,
      renderBehavior: renderBehavior,
    );
  }

  @override
  int contentLength(Item item) => _delegate.contentLength(item);

  TwoSetAttributionManager _createDelegate() {
    return TwoSetAttributionManager(
      inserts: _extractAttributions(
        _attributions.inserts,
        _documentIds(nextDoc).diff(_documentIds(previousDoc)),
      ),
      deletes: _extractAttributions(
        _attributions.deletes,
        _deleteIds(nextDoc).diff(_deleteIds(previousDoc)),
      ),
    );
  }

  void _afterTransaction(Transaction transaction) {
    final changed = ContentIds(
      inserts: transaction.insertSet,
      deletes: transaction.deleteSet,
    );
    if (changed.isEmpty) {
      return;
    }
    _delegate = _createDelegate();
    _change.emit(
      AttributionChangeEvent(
        changed: changed,
        origin: transaction.origin,
        local: transaction.local,
      ),
    );
  }

  ContentIds _selectedChanges(Id start, Id? end) {
    final range = _rangeFromIds(start, end ?? start);
    final selected = ContentIds(
      inserts: IdSet()..addRange(start.client, range),
      deletes: IdSet()..addRange(start.client, range),
    );
    return suggestedChanges.intersect(selected);
  }

  void _syncPreviousUpdate(DocUpdateEvent event) {
    if (!identical(event.origin, this)) {
      applyUpdate(nextDoc, event.update, origin: this);
    }
  }

  void _syncNextUpdate(DocUpdateEvent event) {
    if (!suggestionMode &&
        !identical(event.origin, this) &&
        _originAllowed(event.origin)) {
      applyUpdate(previousDoc, event.update, origin: this);
    }
  }

  bool _originAllowed(Object? origin) {
    final origins = suggestionOrigins;
    return origins == null || origins.contains(origin);
  }
}

/// Attribution manager based on two snapshots.
final class SnapshotAttributionManager extends TwoSetAttributionManager {
  /// Creates a snapshot attribution manager.
  SnapshotAttributionManager(
    Snapshot previousSnapshot, [
    Snapshot? nextSnapshot,
  ]) : super(
          inserts: _snapshotInserts(
            previousSnapshot,
            nextSnapshot ?? previousSnapshot,
          ),
          deletes: (nextSnapshot ?? previousSnapshot)
              .deleteSet
              .diff(previousSnapshot.deleteSet)
              .toAttributedMap(),
        );
}

/// Creates a diff attribution manager.
DiffAttributionManager createAttributionManagerFromDiff(
  Doc previousDoc,
  Doc nextDoc, {
  Attributions? attributions,
}) =>
    DiffAttributionManager(
      previousDoc,
      nextDoc,
      attributions: attributions,
    );

/// Creates a snapshot attribution manager.
SnapshotAttributionManager createAttributionManagerFromSnapshots(
  Snapshot previousSnapshot, [
  Snapshot? nextSnapshot,
]) =>
    SnapshotAttributionManager(previousSnapshot, nextSnapshot);

IdMap _extractAttributions(IdMap attributes, IdSet ids) {
  final attributed = attributes.intersectIdSet(ids);
  final gaps = ids.diff(attributed.toIdSet());
  return attributed.merged(IdMap.fromIdSet(gaps, const <ContentAttribute>[]));
}

IdSet _documentIds(Doc doc) {
  final ids = IdSet();
  for (final client in doc.store.clients) {
    for (final struct in doc.store.structsFor(client)) {
      if (struct is! Item ||
          struct.deleted ||
          struct.ref == contentDeletedRef) {
        continue;
      }
      ids.addRange(client, struct.range);
    }
  }
  return ids;
}

IdSet _deleteIds(Doc doc) =>
    createDeleteSetFromStore(doc.store).merged(doc.store.pendingDeleteSet);

IdMap _snapshotInserts(Snapshot previous, Snapshot next) {
  final ids = IdSet();
  for (final entry in next.stateVector.entries) {
    final previousClock = previous.stateVector[entry.key] ?? Clock(0);
    if (entry.value.value > previousClock.value) {
      ids.addRange(
        entry.key,
        IdRange(
          start: previousClock,
          length: entry.value.value - previousClock.value,
        ),
      );
    }
  }
  return ids.toAttributedMap();
}

IdRange _rangeFromIds(Id start, Id end) {
  if (start.client != end.client) {
    throw ArgumentError.value(end, 'end', 'must use the same client as start');
  }
  if (end.clock.value < start.clock.value) {
    throw ArgumentError.value(end, 'end', 'must not be before start');
  }
  return IdRange(
    start: start.clock,
    length: end.clock.value - start.clock.value + 1,
  );
}

extension on IdSet {
  IdMap toAttributedMap() {
    return IdMap.fromIdSet(this, const <ContentAttribute>[]);
  }
}
