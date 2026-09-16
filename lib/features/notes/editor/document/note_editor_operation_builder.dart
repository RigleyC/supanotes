import 'package:flutter/foundation.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:super_editor/super_editor.dart';

enum NoteEditorOperationKind {
  textDelta('text_delta'),
  createBlock('create_block'),
  deleteBlock('delete_block'),
  moveBlock('move_block'),
  setBlockType('set_block_type'),
  setBlockMetadata('set_block_metadata'),
  completeTaskOccurrence('complete_task_occurrence');

  const NoteEditorOperationKind(this.wireName);

  final String wireName;
}

final class NoteEditorBlockSnapshot {
  const NoteEditorBlockSnapshot({
    required this.id,
    required this.type,
    required this.text,
    required this.metadata,
  });

  factory NoteEditorBlockSnapshot.fromNode(
    DocumentNode node,
    NoteDocumentCodec codec,
  ) {
    final metadata = Map<String, dynamic>.from(node.metadata);
    if (node is TaskNode) {
      metadata['isCompleted'] = node.isComplete;
    }
    if (node is TaskNode && node.indent != 0) {
      metadata['indent'] = node.indent;
    } else if (node is ListItemNode && node.indent != 0) {
      metadata['indent'] = node.indent;
    }

    return NoteEditorBlockSnapshot(
      id: node.id,
      type: codec.blockTypeName(node) ?? 'paragraph',
      text: node is TextNode ? node.text : AttributedText(),
      metadata: metadata,
    );
  }

  final String id;
  final String type;
  final AttributedText text;
  final Map<String, dynamic> metadata;
}

final class NoteEditorDocumentSnapshot {
  NoteEditorDocumentSnapshot(Iterable<NoteEditorBlockSnapshot> blocks)
    : blocks = List<NoteEditorBlockSnapshot>.unmodifiable(blocks);

  factory NoteEditorDocumentSnapshot.fromDocument(
    Document document,
    NoteDocumentCodec codec,
  ) => NoteEditorDocumentSnapshot(
    document.map(
      (node) => NoteEditorBlockSnapshot.fromNode(node, codec),
    ),
  );

  final List<NoteEditorBlockSnapshot> blocks;

  bool get hasComposingText => blocks.any(
    (block) => block.text.spans.markers.any(
      (marker) =>
          marker.markerType == SpanMarkerType.start &&
          marker.attribution.id == 'composing',
    ),
  );
}

final class NoteEditorOperation {
  const NoteEditorOperation({
    required this.kind,
    required this.blockId,
    required this.payload,
  });

  final NoteEditorOperationKind kind;
  final String? blockId;
  final Map<String, dynamic> payload;
}

/// Builds semantic note operations from two immutable editor snapshots.
///
/// This class has no document listener, operation-id generator, or persistence
/// dependency. The capture layer owns those concerns and only adapts these
/// values to the REST/OT outbox contract.
final class NoteEditorOperationBuilder {
  const NoteEditorOperationBuilder({required this.codec});

  final NoteDocumentCodec codec;

  List<NoteEditorOperation> build({
    required NoteEditorDocumentSnapshot before,
    required NoteEditorDocumentSnapshot after,
  }) {
    final beforeById = {
      for (final block in before.blocks) block.id: block,
    };
    final afterIds = after.blocks.map((block) => block.id).toSet();
    final operations = <NoteEditorOperation>[];

    for (final block in before.blocks) {
      if (!afterIds.contains(block.id)) {
        operations.add(
          NoteEditorOperation(
            kind: NoteEditorOperationKind.deleteBlock,
            blockId: block.id,
            payload: {'blockId': block.id},
          ),
        );
      }
    }

    for (var index = 0; index < after.blocks.length; index++) {
      final block = after.blocks[index];
      final afterBlockId = index == 0 ? null : after.blocks[index - 1].id;
      final previous = beforeById[block.id];
      if (previous == null) {
        operations.add(
          NoteEditorOperation(
            kind: NoteEditorOperationKind.createBlock,
            blockId: block.id,
            payload: {
              'id': block.id,
              'type': block.type,
              'delta': codec.encodeAttributedTextToDelta(block.text),
              'metadata': block.metadata,
              'afterBlockId': afterBlockId,
            },
          ),
        );
        continue;
      }

      final previousIndex = before.blocks.indexOf(previous);
      final previousAfterBlockId = previousIndex <= 0
          ? null
          : before.blocks[previousIndex - 1].id;
      if (previousAfterBlockId != afterBlockId) {
        operations.add(
          NoteEditorOperation(
            kind: NoteEditorOperationKind.moveBlock,
            blockId: block.id,
            payload: {
              'blockId': block.id,
              'afterBlockId': afterBlockId,
            },
          ),
        );
      }

      _appendContentOperations(previous, block, operations);
    }

    return operations;
  }

  void _appendContentOperations(
    NoteEditorBlockSnapshot before,
    NoteEditorBlockSnapshot after,
    List<NoteEditorOperation> operations,
  ) {
    if (before.text != after.text) {
      final delta = _computeAttributedTextDelta(before.text, after.text);
      if (delta.isNotEmpty) {
        operations.add(
          NoteEditorOperation(
            kind: NoteEditorOperationKind.textDelta,
            blockId: after.id,
            payload: {'ops': delta},
          ),
        );
      }
    }

    if (before.type != after.type) {
      operations.add(
        NoteEditorOperation(
          kind: NoteEditorOperationKind.setBlockType,
          blockId: after.id,
          payload: {'type': after.type},
        ),
      );
    }

    if (mapEquals(before.metadata, after.metadata)) return;

    final beforeCompletions = Map<String, dynamic>.from(
      before.metadata['completions'] as Map? ?? {},
    );
    final afterCompletions = Map<String, dynamic>.from(
      after.metadata['completions'] as Map? ?? {},
    );

    for (final entry in afterCompletions.entries) {
      if (beforeCompletions[entry.key] == entry.value) continue;
      operations.add(
        NoteEditorOperation(
          kind: NoteEditorOperationKind.completeTaskOccurrence,
          blockId: after.id,
          payload: {
            'taskId': after.id,
            'scheduledAt': entry.key,
            'completedAt': entry.value,
          },
        ),
      );
    }

    for (final key in beforeCompletions.keys) {
      if (afterCompletions.containsKey(key)) continue;
      operations.add(
        NoteEditorOperation(
          kind: NoteEditorOperationKind.completeTaskOccurrence,
          blockId: after.id,
          payload: {
            'taskId': after.id,
            'scheduledAt': key,
            'completedAt': null,
          },
        ),
      );
    }

    final afterOtherMetadata = Map<String, dynamic>.from(after.metadata)
      ..remove('completions');
    final beforeOtherMetadata = Map<String, dynamic>.from(before.metadata)
      ..remove('completions');
    if (!mapEquals(afterOtherMetadata, beforeOtherMetadata)) {
      for (final key in beforeOtherMetadata.keys) {
        if (!afterOtherMetadata.containsKey(key)) {
          afterOtherMetadata[key] = null;
        }
      }
      operations.add(
        NoteEditorOperation(
          kind: NoteEditorOperationKind.setBlockMetadata,
          blockId: after.id,
          payload: {'metadata': afterOtherMetadata},
        ),
      );
    }
  }

  List<Map<String, dynamic>> _computeAttributedTextDelta(
    AttributedText oldText,
    AttributedText newText,
  ) {
    final oldString = oldText.toPlainText();
    final newString = newText.toPlainText();
    if (oldString == newString) {
      return _computeAttributeDelta(oldText, newText, oldString.length);
    }

    final range = _findTextChangeRange(oldString, newString);
    final deletedCount =
        oldString.length - range.prefixLength - range.suffixLength;
    final insertedText = newString.substring(
      range.prefixLength,
      newString.length - range.suffixLength,
    );
    final operations = <Map<String, dynamic>>[];
    if (range.prefixLength > 0) operations.add({'retain': range.prefixLength});
    if (deletedCount > 0) operations.add({'delete': deletedCount});
    if (insertedText.isNotEmpty) {
      final inserted = newText.copyText(
        range.prefixLength,
        range.prefixLength + insertedText.length,
      );
      final insertOperations = codec.encodeAttributedTextToDelta(inserted);
      final insertionIsBold =
          range.prefixLength > 0 &&
          _attributionsAt(oldText, range.prefixLength - 1).contains('bold');
      if (!insertionIsBold) {
        for (final operation in insertOperations) {
          final attributes = operation['attributes'];
          if (attributes is! Map || !attributes.containsKey('bold')) continue;
          final cleanedAttributes = Map<String, dynamic>.from(attributes)
            ..remove('bold');
          if (cleanedAttributes.isEmpty) {
            operation.remove('attributes');
          } else {
            operation['attributes'] = cleanedAttributes;
          }
        }
      }
      operations.addAll(insertOperations);
    }
    return operations;
  }

  List<Map<String, dynamic>> _computeAttributeDelta(
    AttributedText oldText,
    AttributedText newText,
    int textLength,
  ) {
    final operations = <Map<String, dynamic>>[];
    var position = 0;
    while (position < textLength) {
      final attributes = _diffAttributes(
        _attributionsAt(oldText, position),
        _attributionsAt(newText, position),
      );
      final runEnd = _findAttributeRunEnd(
        oldText,
        newText,
        position,
        textLength,
        attributes,
      );
      final operation = <String, dynamic>{'retain': runEnd - position};
      if (attributes.isNotEmpty) operation['attributes'] = attributes;
      operations.add(operation);
      position = runEnd;
    }
    return operations;
  }

  int _findAttributeRunEnd(
    AttributedText oldText,
    AttributedText newText,
    int start,
    int textLength,
    Map<String, dynamic> attributes,
  ) {
    var end = start + 1;
    while (end < textLength) {
      final nextAttributes = _diffAttributes(
        _attributionsAt(oldText, end),
        _attributionsAt(newText, end),
      );
      if (!mapEquals(attributes, nextAttributes)) break;
      end++;
    }
    return end;
  }

  ({int prefixLength, int suffixLength}) _findTextChangeRange(
    String oldText,
    String newText,
  ) {
    var prefixLength = 0;
    while (prefixLength < oldText.length &&
        prefixLength < newText.length &&
        oldText[prefixLength] == newText[prefixLength]) {
      prefixLength++;
    }

    var suffixLength = 0;
    while (suffixLength < oldText.length - prefixLength &&
        suffixLength < newText.length - prefixLength &&
        oldText[oldText.length - suffixLength - 1] ==
            newText[newText.length - suffixLength - 1]) {
      suffixLength++;
    }
    return (prefixLength: prefixLength, suffixLength: suffixLength);
  }

  Set<String> _attributionsAt(AttributedText text, int offset) {
    if (text.toPlainText().isEmpty) return const {};
    final active = <String>{};
    for (final marker in text.spans.markers) {
      final id = NoteDocumentCodec.attributionToName(marker.attribution);
      if (id == 'composing') continue;
      if (marker.markerType == SpanMarkerType.start) {
        if (marker.offset <= offset) active.add(id);
      } else if (marker.markerType == SpanMarkerType.end &&
          marker.offset < offset) {
        active.remove(id);
      }
    }
    return active;
  }

  Map<String, dynamic> _diffAttributes(
    Set<String> oldAttributes,
    Set<String> newAttributes,
  ) {
    final diff = <String, dynamic>{};
    for (final attribute in newAttributes) {
      if (!oldAttributes.contains(attribute)) diff[attribute] = true;
    }
    for (final attribute in oldAttributes) {
      if (!newAttributes.contains(attribute)) diff[attribute] = null;
    }
    return diff;
  }
}
