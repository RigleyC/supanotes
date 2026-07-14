part of 'apply_update.dart';

final class _UpdateIntegrationTarget
    implements ItemIntegrationTarget, NestedContentLifecycleTarget {
  _UpdateIntegrationTarget(this.transaction);

  final Transaction transaction;

  StructStore get store => transaction.doc.store;

  @override
  void addStruct(AbstractStruct struct) {
    store.addStruct(struct);
  }

  @override
  void addInsertedRange(ClientId client, IdRange range) {
    store.addInsertedRange(client, range);
    transaction.addInsertedRange(client, range);
  }

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    store.addDeletedRange(client, range);
    transaction.addDeletedRange(client, range);
  }

  @override
  void addSkippedRange(ClientId client, IdRange range) {
    store.addSkippedRange(client, range);
  }

  @override
  Item? itemContaining(Id id) => store.itemContaining(id);

  @override
  void addChangedParent(ItemParent parent, String? parentSub) {
    transaction.markChanged(parent, parentSub);
  }

  @override
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  }) {}

  @override
  void queueMerge(Item item) {
    transaction.queueMerge(item);
  }

  @override
  void markDeleted(int length) {
    RangeError.checkNotNegative(length, 'length');
  }

  @override
  void clearFormattingCache() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void markHasFormatting() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void addSubdocument(Subdocument document) {
    transaction
      ..addSubdocument(document)
      ..doc.addSubdocument(document);
  }

  @override
  void loadSubdocument(Subdocument document) {
    transaction.loadSubdocument(document);
  }

  @override
  void removeSubdocument(Subdocument document) {
    transaction
      ..removeSubdocument(document)
      ..doc.removeSubdocument(document);
  }

  @override
  void integrateSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void deleteSharedType(SharedTypePlaceholder sharedType) {}

  @override
  void gcSharedType(SharedTypePlaceholder sharedType) {}
}

bool _applyDeleteSet(
  _UpdateIntegrationTarget target,
  IdSet deleteSet,
  Map<ClientId, Clock> missing,
) {
  var applied = false;
  for (final client in deleteSet.clients) {
    for (final range in deleteSet.rangesFor(client)) {
      final localClock = target.store.getClock(client);
      if (localClock.value < range.end) {
        final pendingStart = _maxInt(localClock.value, range.start.value);
        target.store.addPendingDeleteSet(
          IdSet()
            ..addRange(
              client,
              IdRange(
                start: Clock(pendingStart),
                length: range.end - pendingStart,
              ),
            ),
        );
        missing[client] = localClock;
      }
      final knownEnd = _minInt(localClock.value, range.end);
      if (knownEnd <= range.start.value) {
        continue;
      }
      final knownRange = IdRange(
        start: range.start,
        length: knownEnd - range.start.value,
      );
      for (final struct in target.store.structsWithSplitting(
        client: client,
        range: knownRange,
      )) {
        if (struct is Item && !struct.deleted) {
          struct.delete(target);
          applied = true;
        }
      }
    }
  }
  return applied;
}

void _retryPendingStructs(Transaction transaction) {
  final store = transaction.doc.store;
  // Re-apply every pending update to a fixpoint. A pass makes progress in two
  // ways: by draining an update whose dependencies have now arrived (it
  // integrates fully and is not re-pended), or by integrating *some* of a single
  // update's structs whose forward dependencies are only satisfied by structs
  // that appear later in the same update. The canonical case for the latter is a
  // full-state snapshot (`encodeStateAsUpdate` / `mergeUpdates`) of two clients'
  // interleaved concurrent inserts: every struct is present in one update, but
  // resolving its cross-client origins takes one sweep per dependency layer, and
  // the still-incomplete remainder re-pends itself as the same single entry each
  // pass. A pending-*count* metric never decreases there, so it would stop after
  // one retry and silently drop every struct beyond the second layer. Track
  // whether any struct actually integrated instead. Termination is guaranteed:
  // each struct integrates at most once (a newly integrated struct advances its
  // client clock and cannot re-integrate), so a pass that integrates nothing is
  // a true fixpoint and ends the loop.
  while (store.pendingStructUpdates.isNotEmpty) {
    var integratedAny = false;
    for (final entry in store.takePendingStructUpdates()) {
      if (entry.update.isEmpty) {
        continue;
      }
      final applied = _readDecodedUpdate(
        _decoderFor(entry.update, entry.version),
        transaction,
        updateBytes: entry.update,
        version: entry.version,
      );
      integratedAny = integratedAny || applied;
    }
    if (!integratedAny) {
      break;
    }
  }
}

void _retryPendingDeleteSet(Transaction transaction) {
  final pending = transaction.doc.store.pendingDeleteSet;
  if (pending.isEmpty) {
    return;
  }

  transaction.doc.store.clearPendingDeleteSet();
  _applyDeleteSet(
    _UpdateIntegrationTarget(transaction),
    pending,
    <ClientId, Clock>{},
  );
}

int _maxInt(int left, int right) => left > right ? left : right;

int _minInt(int left, int right) => left < right ? left : right;
