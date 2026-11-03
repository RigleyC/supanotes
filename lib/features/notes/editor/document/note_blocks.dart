import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart' as quill;
import 'package:flutter/foundation.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/note_document_constants.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

const _deepEquality = DeepCollectionEquality();

/// One block of a note document, as stored and synced:
/// `{id, type, delta, metadata}`.
///
/// This is the editor-independent document model. The editor widget converts
/// to and from it at its boundary; projection, diffing and sync operate only
/// on these values.
@immutable
final class NoteBlock {
  NoteBlock({
    required this.id,
    required this.type,
    List<Map<String, dynamic>> delta = const [],
    Map<String, dynamic> metadata = const {},
  }) : delta = List.unmodifiable(delta.map(Map<String, dynamic>.unmodifiable)),
       metadata = Map.unmodifiable(metadata);

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    var type = json['type'] as String? ?? 'paragraph';
    final metadata = Map<String, dynamic>.from(
      json['metadata'] as Map? ?? const {},
    );
    // Legacy paragraphs carried their heading/quote style as metadata.
    if (type == 'paragraph' && metadata.containsKey('blockType')) {
      final blockType = metadata.remove('blockType');
      if (blockType is String && legacyParagraphStyles.contains(blockType)) {
        type = blockType == 'blockquote' ? 'quote' : blockType;
      }
    }
    final rawDelta = json['delta'] ?? json['content'];
    return NoteBlock(
      id: json['id'] as String,
      type: type,
      delta: rawDelta is List
          ? [
              for (final op in rawDelta)
                if (op is Map)
                  _normalizeOperation(Map<String, dynamic>.from(op)),
            ]
          : const [],
      metadata: metadata,
    );
  }

  final String id;
  final String type;
  final List<Map<String, dynamic>> delta;
  final Map<String, dynamic> metadata;

  /// Plain text of the block.
  String get text => delta.map((op) => op['insert']).whereType<String>().join();

  bool get isTask => type == 'task';

  int get indent => metadata['indent'] as int? ?? 0;

  NoteBlock copyWith({
    String? id,
    String? type,
    List<Map<String, dynamic>>? delta,
    Map<String, dynamic>? metadata,
  }) => NoteBlock(
    id: id ?? this.id,
    type: type ?? this.type,
    delta: delta ?? this.delta,
    metadata: metadata ?? this.metadata,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'delta': delta,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlock &&
          other.id == id &&
          other.type == type &&
          _deepEquality.equals(other.delta, delta) &&
          _deepEquality.equals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(id, type, _deepEquality.hash(delta));
}

/// Paragraph `blockType` values written by older clients.
const legacyParagraphStyles = {'header1', 'header2', 'header3', 'blockquote'};

/// Legacy `link:<url>: true` attributes become the canonical `link: <url>`.
Map<String, dynamic> _normalizeOperation(Map<String, dynamic> op) {
  final attributes = op['attributes'];
  if (attributes is! Map) return op;
  final normalized = <String, dynamic>{};
  for (final entry in attributes.entries) {
    final key = entry.key as String;
    if (key.startsWith('link:') && entry.value == true) {
      normalized['link'] = key.substring(5);
    } else {
      normalized[key] = entry.value;
    }
  }
  return {...op, 'attributes': normalized};
}

/// Decodes the blocks of a stored snapshot (`{schemaVersion, blocks}`).
///
/// An empty document becomes one empty paragraph, which is what the editor
/// shows for a new note.
List<NoteBlock> noteBlocksFromSnapshot(Map<String, dynamic> snapshot) {
  final rawBlocks = snapshot['blocks'] as List<dynamic>? ?? const [];
  final ids = <String>{};
  final blocks = <NoteBlock>[];
  for (final raw in rawBlocks) {
    final block = NoteBlock.fromJson(Map<String, dynamic>.from(raw as Map));
    if (ids.add(block.id)) blocks.add(block);
  }
  if (blocks.isEmpty) {
    blocks.add(NoteBlock(id: initialNoteBlockId, type: 'paragraph'));
  }
  return blocks;
}

Map<String, dynamic> noteSnapshotFromBlocks(
  List<NoteBlock> blocks, {
  int schemaVersion = 1,
}) => {
  'schemaVersion': schemaVersion,
  'blocks': [
    for (final block in blocks)
      // Stored task blocks always state their completion, as readers of the
      // materialized document expect.
      if (block.type == 'task' && !block.metadata.containsKey('isCompleted'))
        block
            .copyWith(
              metadata: {...block.metadata, 'isCompleted': false},
            )
            .toJson()
      else
        block.toJson(),
  ],
};

/// Applies the canonical snapshot plus durable local operations that the
/// server has not acknowledged yet: the effective local document.
List<NoteBlock> projectNoteBlocks({
  required Map<String, dynamic> snapshot,
  required List<PendingNoteOperationData>? pendingOps,
}) {
  final blocks = noteBlocksFromSnapshot(snapshot);
  for (final op in pendingOps ?? const <PendingNoteOperationData>[]) {
    applyNoteOperation(
      blocks,
      kind: op.kind,
      blockId: op.blockId,
      payload: Map<String, dynamic>.from(jsonDecode(op.payloadJson) as Map),
    );
  }
  return blocks;
}

/// Applies one REST/OT operation to [blocks] in place, with the same
/// semantics as the server: operations that do not fit the current document
/// (unknown block, out-of-range text change) are ignored.
void applyNoteOperation(
  List<NoteBlock> blocks, {
  required String kind,
  required String? blockId,
  required Map<String, dynamic> payload,
}) {
  switch (kind) {
    case NoteOperationWireNames.textDelta:
      _applyTextDelta(blocks, blockId, payload);
    case NoteOperationWireNames.createBlock:
      _applyCreateBlock(blocks, payload);
    case NoteOperationWireNames.deleteBlock:
      _applyDeleteBlock(blocks, blockId, payload);
    case NoteOperationWireNames.moveBlock:
      _applyMoveBlock(blocks, blockId, payload);
    case NoteOperationWireNames.setBlockType:
      _applySetBlockType(blocks, blockId, payload);
    case NoteOperationWireNames.setBlockMetadata:
      _applySetBlockMetadata(blocks, blockId, payload);
    case NoteOperationWireNames.completeTaskOccurrence:
      _applyCompleteTaskOccurrence(blocks, blockId, payload);
  }
}

int _indexOfBlock(List<NoteBlock> blocks, String? id) =>
    id == null ? -1 : blocks.indexWhere((block) => block.id == id);

void _applyTextDelta(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final index = _indexOfBlock(blocks, blockId);
  final rawOps = payload['ops'];
  if (index < 0 || rawOps is! List) return;
  final delta = composeBlockDelta(
    blocks[index].delta,
    [for (final op in rawOps) Map<String, dynamic>.from(op as Map)],
  );
  if (delta != null) blocks[index] = blocks[index].copyWith(delta: delta);
}

void _applyCreateBlock(List<NoteBlock> blocks, Map<String, dynamic> payload) {
  final block = NoteBlock.fromJson(payload);
  if (_indexOfBlock(blocks, block.id) >= 0) return;
  final afterBlockId = payload['afterBlockId'] as String?;
  var index = blocks.length;
  if (afterBlockId == null) {
    index = 0;
  } else {
    final target = _indexOfBlock(blocks, afterBlockId);
    if (target >= 0) index = target + 1;
  }
  blocks.insert(index.clamp(0, blocks.length), block);
}

void _applyDeleteBlock(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final index = _indexOfBlock(blocks, blockId ?? payload['blockId'] as String?);
  if (index >= 0 && blocks.length > 1) blocks.removeAt(index);
}

void _applyMoveBlock(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final moveId = payload['blockId'] as String? ?? blockId;
  final source = _indexOfBlock(blocks, moveId);
  if (source < 0 || blocks.length <= 1) return;
  final afterId = payload['afterBlockId'] as String?;
  if (afterId == moveId) return;
  final target = _moveTarget(blocks, source, afterId);
  final block = blocks.removeAt(source);
  blocks.insert(target.clamp(0, blocks.length), block);
}

/// Index the block at [source] lands on, counted before it is removed.
int _moveTarget(List<NoteBlock> blocks, int source, String? afterId) {
  if (afterId == null) return 0;
  final afterIndex = _indexOfBlock(blocks, afterId);
  if (afterIndex < 0) return blocks.length - 1;
  return source < afterIndex ? afterIndex : afterIndex + 1;
}

void _applySetBlockType(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final index = _indexOfBlock(blocks, blockId);
  if (index < 0) return;
  blocks[index] = blocks[index].copyWith(
    type: payload['type'] as String? ?? 'paragraph',
  );
}

void _applySetBlockMetadata(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final index = _indexOfBlock(blocks, blockId);
  final updates = payload['metadata'];
  if (index < 0 || updates is! Map) return;
  blocks[index] = blocks[index].copyWith(
    metadata: mergeNoteMetadata(
      blocks[index].metadata,
      Map<String, dynamic>.from(updates),
    ),
  );
}

void _applyCompleteTaskOccurrence(
  List<NoteBlock> blocks,
  String? blockId,
  Map<String, dynamic> payload,
) {
  final index = _indexOfBlock(blocks, blockId ?? payload['taskId'] as String?);
  final scheduledAt = payload['scheduledAt'] as String?;
  if (index < 0 || !blocks[index].isTask || scheduledAt == null) return;
  final completions = Map<String, dynamic>.from(
    blocks[index].metadata['completions'] as Map? ?? const {},
  );
  final completedAt = payload['completedAt'] as String?;
  if (completedAt != null && completedAt.isNotEmpty) {
    completions[scheduledAt] = completedAt;
  } else {
    completions.remove(scheduledAt);
  }
  blocks[index] = blocks[index].copyWith(
    metadata: {...blocks[index].metadata, 'completions': completions},
  );
}

/// Merges metadata [updates]; a `null` value removes the key.
Map<String, dynamic> mergeNoteMetadata(
  Map<String, dynamic> current,
  Map<String, dynamic> updates,
) {
  final merged = Map<String, dynamic>.from(current);
  for (final entry in updates.entries) {
    if (entry.value == null) {
      merged.remove(entry.key);
    } else {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

/// Composes text change [ops] onto a block [delta]. Returns `null` when the
/// change is malformed or reaches past the end of the text.
List<Map<String, dynamic>>? composeBlockDelta(
  List<Map<String, dynamic>> delta,
  List<Map<String, dynamic>> ops,
) {
  var consumed = 0;
  final length = delta.fold<int>(
    0,
    (sum, op) => sum + ((op['insert'] as String?)?.length ?? 0),
  );
  for (final op in ops) {
    final span = _textOpSpan(op);
    if (span == null) return null;
    consumed += span;
    if (consumed > length) return null;
  }
  final composed = _toQuill(delta).compose(_toQuill(ops));
  return _fromQuill(composed);
}

/// How much existing text a change [op] retains or deletes (0 for an
/// insert), or `null` when the op is malformed.
int? _textOpSpan(Map<String, dynamic> op) {
  final keys = const ['insert', 'retain', 'delete'].where(op.containsKey);
  if (keys.length != 1) return null;
  final attributes = op['attributes'];
  if (attributes != null && attributes is! Map) return null;
  final value = op[keys.single];
  if (keys.single == 'insert') return value is String ? 0 : null;
  return value is int && value >= 0 ? value : null;
}

/// The text change that turns block delta [before] into [after], or an empty
/// list when they are equal.
List<Map<String, dynamic>> diffBlockDelta(
  List<Map<String, dynamic>> before,
  List<Map<String, dynamic>> after,
) {
  if (_deepEquality.equals(before, after)) return const [];
  final change = _toQuill(before).diff(_toQuill(after), cleanupSemantic: false);
  return _fromQuill(change);
}

quill.Delta _toQuill(List<Map<String, dynamic>> ops) =>
    ops.isEmpty ? quill.Delta() : quill.Delta.fromJson(ops);

List<Map<String, dynamic>> _fromQuill(quill.Delta delta) => [
  for (final op in delta.toJson()) Map<String, dynamic>.from(op as Map),
];

/// One REST/OT operation produced by comparing two editor states.
@immutable
final class NoteBlockOperation {
  const NoteBlockOperation({
    required this.kind,
    required this.blockId,
    required this.payload,
  });

  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
}

/// Builds the REST/OT operations that turn [before] into [after].
///
/// Block identity is the block id: a block present in both lists gets text,
/// type, metadata and move operations; others are created or deleted.
List<NoteBlockOperation> diffNoteBlocks(
  List<NoteBlock> before,
  List<NoteBlock> after,
) {
  final beforeById = {for (final block in before) block.id: block};
  final afterIds = {for (final block in after) block.id};
  final operations = <NoteBlockOperation>[];
  final stable = _stableBlockIds(before, after, beforeById);

  for (var index = 0; index < after.length; index++) {
    _appendBlockOperations(
      previous: beforeById[after[index].id],
      block: after[index],
      afterBlockId: index == 0 ? null : after[index - 1].id,
      stable: stable,
      operations: operations,
    );
  }

  // Deletions go last: a document never loses its final block, so deleting
  // first would keep a block alive when every block is replaced.
  for (final block in before) {
    if (afterIds.contains(block.id)) continue;
    operations.add(
      NoteBlockOperation(
        kind: NoteOperationWireNames.deleteBlock,
        blockId: block.id,
        payload: NoteOperationPayloads.deleteBlock(block.id),
      ),
    );
  }
  return operations;
}

/// Ids of the blocks present in both states that do not need a move.
///
/// Blocks present in both states keep their relative order except the ones
/// that moved. The largest set that kept its order (longest increasing
/// subsequence of previous positions) stays put; only the rest get a
/// move_block, so one move yields one operation.
Set<String> _stableBlockIds(
  List<NoteBlock> before,
  List<NoteBlock> after,
  Map<String, NoteBlock> beforeById,
) {
  final beforeIndex = {
    for (var i = 0; i < before.length; i++) before[i].id: i,
  };
  final survivors = [
    for (final block in after)
      if (beforeById.containsKey(block.id)) block.id,
  ];
  return _longestIncreasingRun(
    [for (final id in survivors) beforeIndex[id]!],
  ).map((position) => survivors[position]).toSet();
}

/// Operations for one block of the new state: a create when it is new,
/// otherwise a move (unless [stable]) and its content changes.
void _appendBlockOperations({
  required NoteBlock? previous,
  required NoteBlock block,
  required String? afterBlockId,
  required Set<String> stable,
  required List<NoteBlockOperation> operations,
}) {
  if (previous == null) {
    operations.add(
      NoteBlockOperation(
        kind: NoteOperationWireNames.createBlock,
        blockId: block.id,
        payload: NoteOperationPayloads.createBlock(
          block: block.toJson()..['metadata'] = block.metadata,
          afterBlockId: afterBlockId,
        ),
      ),
    );
    return;
  }

  if (!stable.contains(block.id)) {
    operations.add(
      NoteBlockOperation(
        kind: NoteOperationWireNames.moveBlock,
        blockId: block.id,
        payload: NoteOperationPayloads.moveBlock(
          blockId: block.id,
          afterBlockId: afterBlockId,
        ),
      ),
    );
  }
  _appendContentOperations(previous, block, operations);
}

/// Positions (into [values]) of one longest strictly increasing subsequence.
List<int> _longestIncreasingRun(List<int> values) {
  final tailValues = <int>[];
  final tailPositions = <int>[];
  final previous = List<int>.filled(values.length, -1);
  for (var i = 0; i < values.length; i++) {
    var low = 0;
    var high = tailValues.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (tailValues[mid] < values[i]) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) previous[i] = tailPositions[low - 1];
    if (low == tailValues.length) {
      tailValues.add(values[i]);
      tailPositions.add(i);
    } else {
      tailValues[low] = values[i];
      tailPositions[low] = i;
    }
  }
  final result = <int>[];
  var position = tailPositions.isEmpty ? -1 : tailPositions.last;
  while (position >= 0) {
    result.add(position);
    position = previous[position];
  }
  return result.reversed.toList();
}

void _appendContentOperations(
  NoteBlock before,
  NoteBlock after,
  List<NoteBlockOperation> operations,
) {
  final ops = diffBlockDelta(before.delta, after.delta);
  if (ops.isNotEmpty) {
    operations.add(
      NoteBlockOperation(
        kind: NoteOperationWireNames.textDelta,
        blockId: after.id,
        payload: NoteOperationPayloads.textDelta(ops: ops),
      ),
    );
  }

  if (before.type != after.type) {
    operations.add(
      NoteBlockOperation(
        kind: NoteOperationWireNames.setBlockType,
        blockId: after.id,
        payload: NoteOperationPayloads.setBlockType(after.type),
      ),
    );
  }

  if (_deepEquality.equals(before.metadata, after.metadata)) return;

  final scheduleChanged = _scheduleChanged(before.metadata, after.metadata);

  // Completing one occurrence is its own operation so two devices completing
  // different occurrences merge instead of overwriting each other.
  if (!scheduleChanged) _appendCompletionOperations(before, after, operations);

  _appendOtherMetadataOperation(before, after, scheduleChanged, operations);
}

bool _scheduleChanged(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) =>
    before['dueDate'] != after['dueDate'] ||
    (before['hasTime'] as bool? ?? false) !=
        (after['hasTime'] as bool? ?? false) ||
    before['recurrenceRule'] != after['recurrenceRule'];

void _appendCompletionOperations(
  NoteBlock before,
  NoteBlock after,
  List<NoteBlockOperation> operations,
) {
  final beforeCompletions = Map<String, dynamic>.from(
    before.metadata['completions'] as Map? ?? const {},
  );
  final afterCompletions = Map<String, dynamic>.from(
    after.metadata['completions'] as Map? ?? const {},
  );
  for (final entry in afterCompletions.entries) {
    if (beforeCompletions[entry.key] == entry.value) continue;
    operations.add(
      _completeOccurrenceOperation(after.id, entry.key, entry.value as String?),
    );
  }
  for (final key in beforeCompletions.keys) {
    if (afterCompletions.containsKey(key)) continue;
    operations.add(_completeOccurrenceOperation(after.id, key, null));
  }
}

NoteBlockOperation _completeOccurrenceOperation(
  String taskId,
  String scheduledAt,
  String? completedAt,
) => NoteBlockOperation(
  kind: NoteOperationWireNames.completeTaskOccurrence,
  blockId: taskId,
  payload: NoteOperationPayloads.completeTaskOccurrence(
    taskId: taskId,
    scheduledAt: scheduledAt,
    completedAt: completedAt,
  ),
);

/// A set_block_metadata for every metadata change other than completions;
/// a schedule change also clears the completions.
void _appendOtherMetadataOperation(
  NoteBlock before,
  NoteBlock after,
  bool scheduleChanged,
  List<NoteBlockOperation> operations,
) {
  final afterOther = Map<String, dynamic>.from(after.metadata)
    ..remove('completions');
  final beforeOther = Map<String, dynamic>.from(before.metadata)
    ..remove('completions');
  if (scheduleChanged) afterOther['completions'] = null;
  if (_deepEquality.equals(afterOther, beforeOther)) return;
  for (final key in beforeOther.keys) {
    afterOther.putIfAbsent(key, () => null);
  }
  operations.add(
    NoteBlockOperation(
      kind: NoteOperationWireNames.setBlockMetadata,
      blockId: after.id,
      payload: NoteOperationPayloads.setBlockMetadata(afterOther),
    ),
  );
}
