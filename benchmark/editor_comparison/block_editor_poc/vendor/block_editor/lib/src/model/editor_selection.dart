import 'package:block_editor/block_editor.dart';
import 'package:meta/meta.dart';

/// A single point within the document, identified by a block and a character
/// offset within that block's [TextDelta].
///
/// Offsets are zero-based and refer to UTF-16 code unit positions, consistent
/// with Dart's [String] indexing semantics.
@immutable
class SelectionPoint {
  /// Creates a [SelectionPoint] at [offset] within the block identified by
  /// [blockId].
  const SelectionPoint({required this.blockId, required this.offset});

  /// The id of the [BlockNode] this point falls within.
  final String blockId;

  /// The zero-based character offset within the block's [TextDelta].
  final int offset;

  /// Returns a copy of this point with the given fields replaced.
  SelectionPoint copyWith({String? blockId, int? offset}) {
    return SelectionPoint(
      blockId: blockId ?? this.blockId,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelectionPoint &&
      other.blockId == blockId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(blockId, offset);

  @override
  String toString() => 'SelectionPoint($blockId, $offset)';
}

/// The ordered start and end points of an [ExpandedSelection], resolved
/// against a known document order.
@immutable
class ResolvedExpansion {
  /// Creates a [ResolvedExpansion] with the given ordered [start] and [end].
  const ResolvedExpansion({required this.start, required this.end});

  /// The earlier point in document order.
  final SelectionPoint start;

  /// The later point in document order.
  final SelectionPoint end;
}

/// The selection state of the editor.
///
/// Use [EditorSelection.none] when no selection is active. Switch exhaustively
/// on this sealed class to handle all cases without null checks.
sealed class EditorSelection {
  const EditorSelection();

  /// The sentinel representing no active selection.
  static const EditorSelection none = NoSelection._();
}

/// Represents the absence of any selection. Use [EditorSelection.none] rather
/// than constructing this directly.
final class NoSelection extends EditorSelection {
  const NoSelection._();
}

/// A collapsed cursor — a single insertion point with no extent.
final class CollapsedSelection extends EditorSelection {
  /// Creates a collapsed cursor at [point].
  const CollapsedSelection(this.point);

  /// The insertion point.
  final SelectionPoint point;

  /// Returns a copy with the given fields replaced.
  CollapsedSelection copyWith({SelectionPoint? point}) {
    return CollapsedSelection(point ?? this.point);
  }

  @override
  bool operator ==(Object other) =>
      other is CollapsedSelection && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => 'CollapsedSelection($point)';
}

/// An expanded selection with an anchor and a focus, potentially spanning
/// multiple blocks.
///
/// [anchor] is where the selection started (e.g. mousedown). [focus] is where
/// it currently ends (e.g. mousemove or shift-arrow). Either point may precede
/// the other in document order — use [resolveOrder] to obtain an ordered
/// [ResolvedExpansion].
final class ExpandedSelection extends EditorSelection {
  /// Creates an [ExpandedSelection] with the given [anchor] and [focus].
  const ExpandedSelection({required this.anchor, required this.focus});

  /// The fixed origin of the selection.
  final SelectionPoint anchor;

  /// The moveable end of the selection.
  final SelectionPoint focus;

  /// Resolves document order using [flattenedBlockIds], which must be the
  /// result of [BlockDocument.flatten] mapped to block ids.
  ///
  /// If [anchor] and [focus] are in the same block, offset order is used.
  /// If a block id is not found in [flattenedBlockIds], the anchor is treated
  /// as the start.
  ResolvedExpansion resolveOrder(List<String> flattenedBlockIds) {
    final anchorIndex = flattenedBlockIds.indexOf(anchor.blockId);
    final focusIndex = flattenedBlockIds.indexOf(focus.blockId);

    if (anchorIndex < focusIndex) {
      return ResolvedExpansion(start: anchor, end: focus);
    }
    if (focusIndex < anchorIndex) {
      return ResolvedExpansion(start: focus, end: anchor);
    }
    if (anchor.offset <= focus.offset) {
      return ResolvedExpansion(start: anchor, end: focus);
    }
    return ResolvedExpansion(start: focus, end: anchor);
  }

  /// Returns a copy with the given fields replaced.
  ExpandedSelection copyWith({SelectionPoint? anchor, SelectionPoint? focus}) {
    return ExpandedSelection(
      anchor: anchor ?? this.anchor,
      focus: focus ?? this.focus,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExpandedSelection &&
      other.anchor == anchor &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(anchor, focus);

  @override
  String toString() => 'ExpandedSelection(anchor: $anchor, focus: $focus)';
}
