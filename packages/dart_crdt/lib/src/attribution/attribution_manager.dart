/// Attribution manager contracts and basic implementations.
library;

import '../content/content.dart';
import '../metadata/content_attribute.dart';
import '../metadata/content_map.dart';
import '../metadata/id_map.dart';
import '../metadata/id_range.dart';
import '../structs/abstract_struct.dart';
import '../structs/id.dart';

/// Immutable insert/delete attribution maps.
final class Attributions {
  /// Creates attribution maps with defensive copies.
  factory Attributions({
    IdMap? inserts,
    IdMap? deletes,
  }) {
    return Attributions._(
      inserts: _copyIdMap(inserts ?? IdMap()),
      deletes: _copyIdMap(deletes ?? IdMap()),
    );
  }

  const Attributions._({
    required IdMap inserts,
    required IdMap deletes,
  })  : _inserts = inserts,
        _deletes = deletes;

  /// Creates empty attribution maps.
  factory Attributions.empty() => Attributions();

  /// Creates attributions from an existing content map.
  factory Attributions.fromContentMap(ContentMap contentMap) {
    return Attributions(
      inserts: contentMap.inserts,
      deletes: contentMap.deletes,
    );
  }

  final IdMap _inserts;
  final IdMap _deletes;

  /// Insert attributions as a defensive copy.
  IdMap get inserts => _copyIdMap(_inserts);

  /// Delete attributions as a defensive copy.
  IdMap get deletes => _copyIdMap(_deletes);

  /// Whether both maps are empty.
  bool get isEmpty => _inserts.isEmpty && _deletes.isEmpty;

  /// Converts to a content map.
  ContentMap toContentMap() => ContentMap(inserts: _inserts, deletes: _deletes);

  /// Returns ranges whose attributes satisfy the supplied predicates.
  Attributions filter({
    required bool Function(List<ContentAttribute> attributes) insertPredicate,
    bool Function(List<ContentAttribute> attributes)? deletePredicate,
  }) {
    return Attributions(
      inserts: _inserts.filter(insertPredicate),
      deletes: _deletes.filter(deletePredicate ?? insertPredicate),
    );
  }
}

/// Controls whether attributed content should be rendered by consumers.
enum AttributionRenderBehavior {
  /// Never render solely because attribution was requested.
  never,

  /// Render when visible or when attribution metadata exists.
  whenVisibleOrAttributed,

  /// Always render the segment.
  always,
}

/// Content plus attribution metadata for a contiguous clock range.
final class AttributedContent {
  /// Creates an attributed content segment.
  AttributedContent({
    required this.content,
    required this.clock,
    required this.deleted,
    Iterable<ContentAttribute>? attributes,
    this.renderBehavior = AttributionRenderBehavior.whenVisibleOrAttributed,
  }) : attributes = attributes == null
            ? null
            : List<ContentAttribute>.unmodifiable(attributes);

  /// Content segment.
  final AbstractContent content;

  /// First clock represented by [content].
  final Clock clock;

  /// Whether the source item is deleted.
  final bool deleted;

  /// Attribution metadata, or `null` for unattributed ranges.
  final List<ContentAttribute>? attributes;

  /// Render behavior requested by the caller.
  final AttributionRenderBehavior renderBehavior;

  /// Whether this segment should be rendered by attribution-aware consumers.
  bool get render {
    return switch (renderBehavior) {
      AttributionRenderBehavior.never => false,
      AttributionRenderBehavior.whenVisibleOrAttributed =>
        !deleted || attributes != null,
      AttributionRenderBehavior.always => true,
    };
  }
}

/// Associates attribution metadata with content items.
abstract interface class AttributionManager {
  /// Reads [content] at [client]/[clock] into attributed content segments.
  List<AttributedContent> readContent({
    required ClientId client,
    required Clock clock,
    required bool deleted,
    required AbstractContent content,
    AttributionRenderBehavior renderBehavior =
        AttributionRenderBehavior.whenVisibleOrAttributed,
  });

  /// Returns the visible attributed length for [item].
  int contentLength(Item item);
}

/// Attribution manager that treats all content as unattributed.
final class NoAttributionManager implements AttributionManager {
  /// Creates a no-attribution manager.
  const NoAttributionManager();

  @override
  List<AttributedContent> readContent({
    required ClientId client,
    required Clock clock,
    required bool deleted,
    required AbstractContent content,
    AttributionRenderBehavior renderBehavior =
        AttributionRenderBehavior.whenVisibleOrAttributed,
  }) {
    if (deleted && renderBehavior == AttributionRenderBehavior.never) {
      return const <AttributedContent>[];
    }
    return <AttributedContent>[
      AttributedContent(
        content: content,
        clock: clock,
        deleted: deleted,
        renderBehavior: renderBehavior,
      ),
    ];
  }

  @override
  int contentLength(Item item) {
    return item.deleted || !item.content.isCountable ? 0 : item.length;
  }
}

/// Shared no-attribution manager instance.
const NoAttributionManager noAttributionManager = NoAttributionManager();

/// Attribution manager backed by separate insert and delete id maps.
class TwoSetAttributionManager implements AttributionManager {
  /// Creates an attribution manager from [inserts] and [deletes].
  TwoSetAttributionManager({
    IdMap? inserts,
    IdMap? deletes,
  })  : _inserts = _copyIdMap(inserts ?? IdMap()),
        _deletes = _copyIdMap(deletes ?? IdMap());

  final IdMap _inserts;
  final IdMap _deletes;

  /// Insert attribution map as a defensive copy.
  IdMap get inserts => _copyIdMap(_inserts);

  /// Delete attribution map as a defensive copy.
  IdMap get deletes => _copyIdMap(_deletes);

  @override
  List<AttributedContent> readContent({
    required ClientId client,
    required Clock clock,
    required bool deleted,
    required AbstractContent content,
    AttributionRenderBehavior renderBehavior =
        AttributionRenderBehavior.whenVisibleOrAttributed,
  }) {
    final slices = (deleted ? _deletes : _inserts).slice(
      client: client,
      range: IdRange(start: clock, length: content.length),
    );
    var remaining = slices.length == 1 ? content : content.copy();
    final result = <AttributedContent>[];
    for (final slice in slices) {
      final segment = remaining;
      if (slice.idRange.length < segment.length) {
        remaining = segment.splice(slice.idRange.length);
      }
      final attributes = slice.attributes;
      if (!deleted ||
          attributes != null ||
          renderBehavior != AttributionRenderBehavior.never) {
        result.add(
          AttributedContent(
            content: segment,
            clock: slice.idRange.start,
            deleted: deleted,
            attributes: attributes,
            renderBehavior: renderBehavior,
          ),
        );
      }
    }
    return List<AttributedContent>.unmodifiable(result);
  }

  @override
  int contentLength(Item item) {
    if (!item.content.isCountable) {
      return 0;
    }
    if (!item.deleted) {
      return item.length;
    }
    var length = 0;
    for (final slice in _deletes.sliceId(item.id, length: item.length)) {
      if (slice.attributes != null) {
        length += slice.idRange.length;
      }
    }
    return length;
  }
}

IdMap _copyIdMap(IdMap source) {
  final copy = IdMap();
  source.insertInto(copy);
  return copy;
}
