part of 'doc.dart';

void _cleanupFormatting(Transaction transaction) {
  if (!transaction.shouldCleanupFormatting) {
    return;
  }
  for (final target in transaction.changed.keys) {
    if (target is ItemParent) {
      _cleanupParentFormatting(transaction, target);
    } else if (target is SharedType) {
      _cleanupSharedTypeFormatting(target);
    }
  }
}

void _cleanupSharedTypeFormatting(SharedType type) {
  if (type.kind == SharedTypeKind.text || type.kind == SharedTypeKind.xmlText) {
    type._ensureTextAttributes();
  }
}

void _cleanupParentFormatting(Transaction transaction, ItemParent parent) {
  final target = _FormattingCleanupTarget(transaction);
  final active = <String, JsonValue>{};
  final gap = <Item>[];
  var sawContent = false;
  for (final item in parent.items()) {
    if (item.deleted) {
      continue;
    }
    final content = item.content;
    if (content is ContentFormat) {
      gap.add(item);
      continue;
    }
    _cleanupFormatGap(target, active, gap, hasFollowingContent: true);
    gap.clear();
    sawContent = true;
  }
  if (sawContent) {
    _cleanupFormatGap(target, active, gap, hasFollowingContent: false);
  }
}

void _cleanupFormatGap(
  _FormattingCleanupTarget target,
  Map<String, JsonValue> active,
  List<Item> gap, {
  required bool hasFollowingContent,
}) {
  if (gap.isEmpty) {
    return;
  }
  if (!hasFollowingContent) {
    _deleteFormatItems(target, gap);
    return;
  }
  final lastByKey = <String, Item>{};
  for (final item in gap) {
    lastByKey[(item.content as ContentFormat).key] = item;
  }
  for (final item in gap) {
    final content = item.content as ContentFormat;
    final isLast = identical(lastByKey[content.key], item);
    final isNoOp = _formatValueEquals(active[content.key], content.value);
    if (!isLast || isNoOp) {
      item.delete(target);
    } else if (content.value == const JsonNull()) {
      active.remove(content.key);
    } else {
      active[content.key] = content.value;
    }
  }
}

void _deleteFormatItems(
  _FormattingCleanupTarget target,
  Iterable<Item> items,
) {
  for (final item in items) {
    item.delete(target);
  }
}

bool _formatValueEquals(JsonValue? left, JsonValue right) {
  return (left == null && right == const JsonNull()) || left == right;
}

final class _FormattingCleanupTarget implements ItemIntegrationTarget {
  _FormattingCleanupTarget(this.transaction);

  final Transaction transaction;

  @override
  void addChangedParent(ItemParent parent, String? parentSub) {
    transaction.markChanged(parent, parentSub);
  }

  @override
  void addDeletedRange(ClientId client, IdRange range) {
    transaction
      ..addDeletedRange(client, range)
      ..doc.store.addDeletedRange(client, range);
  }

  @override
  void addInsertedRange(ClientId client, IdRange range) {}

  @override
  void addSkippedRange(ClientId client, IdRange range) {}

  @override
  void addStruct(AbstractStruct struct) {}

  @override
  void clearFormattingCache() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  Item? itemContaining(Id id) => transaction.doc.store.itemContaining(id);

  @override
  void markDeleted(int length) => RangeError.checkNotNegative(length, 'length');

  @override
  void markHasFormatting() {
    transaction.shouldCleanupFormatting = true;
  }

  @override
  void queueMerge(Item item) => transaction.queueMerge(item);

  @override
  void updateSearchMarkers({
    required ItemParent parent,
    required Item item,
    required int lengthDelta,
  }) {}
}
