/// Content-id extraction and update intersection helpers.
library;

import 'dart:typed_data';

import '../content/content.dart';
import '../doc/doc.dart';
import '../metadata/content_ids.dart';
import '../metadata/id_range.dart';
import '../metadata/id_set.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';
import '../structs/struct_store.dart';
import 'apply_update.dart';
import 'state_update.dart';
import 'update_inspection.dart';

/// Extracts inserted and deleted content ids from a V1 [update].
ContentIds createContentIdsFromUpdate(List<int> update) {
  return _contentIdsFromDecoded(decodeUpdate(update));
}

/// Extracts inserted and deleted content ids from a V2 [update].
ContentIds createContentIdsFromUpdateV2(List<int> update) {
  return _contentIdsFromDecoded(decodeUpdateV2(update));
}

/// Returns the V1 subset of [update] selected by [contentIds].
Uint8List intersectUpdateWithContentIds(
  List<int> update,
  ContentIds contentIds,
) {
  final doc = Doc();
  applyUpdate(doc, update);
  final filtered = _filterDoc(doc, contentIds);
  return encodeStateAsUpdate(filtered);
}

/// Returns the V2 subset of [update] selected by [contentIds].
Uint8List intersectUpdateWithContentIdsV2(
  List<int> update,
  ContentIds contentIds,
) {
  final doc = Doc();
  applyUpdateV2(doc, update);
  final filtered = _filterDoc(doc, contentIds);
  return encodeStateAsUpdateV2(filtered);
}

ContentIds _contentIdsFromDecoded(DecodedUpdate decoded) {
  final inserts = IdSet();
  for (final struct in decoded.structs) {
    if (struct.ref == structSkipRefNumber || struct.ref == structGcRefNumber) {
      continue;
    }
    inserts.addRange(
      struct.id.client,
      IdRange(start: struct.id.clock, length: struct.length),
    );
  }
  return ContentIds(inserts: inserts, deletes: decoded.deleteSet);
}

Doc _filterDoc(Doc source, ContentIds contentIds) {
  final result = Doc();
  _copySelectedStructs(
    source: source,
    target: result,
    selected: contentIds.inserts,
  );
  result.store.addPendingDeleteSet(
    _deleteIdsFor(source).intersect(contentIds.deletes),
  );
  return result;
}

IdSet _deleteIdsFor(Doc doc) {
  return createDeleteSetFromStore(doc.store).merged(doc.store.pendingDeleteSet);
}

void _copySelectedStructs({
  required Doc source,
  required Doc target,
  required IdSet selected,
}) {
  for (final client in selected.clients) {
    var nextClock = 0;
    for (final range in selected.rangesFor(client)) {
      for (final slice in source.store.slicesWithoutSplitting(
        client: client,
        range: range,
      )) {
        if (slice.range.start.value > nextClock) {
          target.store.add(
            Skip(
              id: Id(client: client, clock: Clock(nextClock)),
              length: slice.range.start.value - nextClock,
            ),
          );
        }
        target.store.add(_copySlice(slice, target, selected));
        nextClock = slice.range.end;
      }
    }
  }
}

AbstractStruct _copySlice(StructSlice slice, Doc target, IdSet selected) {
  final struct = slice.struct;
  if (struct is GC) {
    return GC(id: slice.id, length: slice.length);
  }
  if (struct is Skip) {
    return Skip(id: slice.id, length: slice.length);
  }
  if (struct is Item) {
    return Item(
      id: slice.id,
      origin: _selectedOrigin(struct, slice, selected),
      rightOrigin: _selectedRightOrigin(struct, selected),
      parent: target.itemParentForKey(struct.parent?.key ?? 'root'),
      parentSub: struct.parentSub,
      content: _sliceContent(
        struct.content,
        offset: slice.offset,
        length: slice.length,
      ),
    );
  }
  throw StateError('Unsupported struct type ${struct.runtimeType}.');
}

Id? _selectedOrigin(Item struct, StructSlice slice, IdSet selected) {
  final origin =
      slice.offset == 0 ? struct.origin : struct.id.advance(slice.offset - 1);
  return origin != null && selected.hasId(origin) ? origin : null;
}

Id? _selectedRightOrigin(Item struct, IdSet selected) {
  final rightOrigin = struct.rightOrigin;
  return rightOrigin != null && selected.hasId(rightOrigin)
      ? rightOrigin
      : null;
}

AbstractContent _sliceContent(
  AbstractContent content, {
  required int offset,
  required int length,
}) {
  if (offset == 0 && length == content.length) {
    return content.copy();
  }
  return switch (content) {
    ContentAny(:final values) => ContentAny(values.skip(offset).take(length)),
    ContentJson(:final values) => ContentJson(values.skip(offset).take(length)),
    ContentString(:final value) => ContentString(
        value.substring(offset, offset + length),
      ),
    ContentDeleted() => ContentDeleted(length),
    _ => throw StateError('Cannot partially slice ${content.runtimeType}.'),
  };
}
