/// Wire-level names and payload rules for REST/OT note operations.
///
/// The Go noteoperations package is the server-side owner of this contract.
/// This module keeps the Flutter adapter and editor code on the same wire
/// vocabulary and rejects malformed locally captured operations before they
/// enter the outbox.
abstract final class NoteOperationWireNames {
  static const textDelta = 'text_delta';
  static const createBlock = 'create_block';
  static const deleteBlock = 'delete_block';
  static const moveBlock = 'move_block';
  static const setBlockType = 'set_block_type';
  static const setBlockMetadata = 'set_block_metadata';
  static const completeTaskOccurrence = 'complete_task_occurrence';
}

enum NoteOperationKind {
  textDelta(NoteOperationWireNames.textDelta),
  createBlock(NoteOperationWireNames.createBlock),
  deleteBlock(NoteOperationWireNames.deleteBlock),
  moveBlock(NoteOperationWireNames.moveBlock),
  setBlockType(NoteOperationWireNames.setBlockType),
  setBlockMetadata(NoteOperationWireNames.setBlockMetadata),
  completeTaskOccurrence(NoteOperationWireNames.completeTaskOccurrence);

  const NoteOperationKind(this.wireName);

  final String wireName;

  static NoteOperationKind? tryParse(String wireName) {
    for (final kind in values) {
      if (kind.wireName == wireName) return kind;
    }
    return null;
  }
}

abstract final class NoteOperationPayloads {
  static Map<String, dynamic> textDelta({
    required List<Map<String, dynamic>> ops,
  }) => {'ops': ops};

  static Map<String, dynamic> createBlock({
    required Map<String, dynamic> block,
    required String? afterBlockId,
  }) => {
    'id': block['id'],
    'type': block['type'],
    'delta': block['delta'],
    'metadata': block['metadata'],
    'afterBlockId': afterBlockId,
  };

  static Map<String, dynamic> deleteBlock(String blockId) => {
    'blockId': blockId,
  };

  static Map<String, dynamic> moveBlock({
    required String blockId,
    required String? afterBlockId,
  }) => {'blockId': blockId, 'afterBlockId': afterBlockId};

  static Map<String, dynamic> setBlockType(String type) => {'type': type};

  static Map<String, dynamic> setBlockMetadata(Map<String, dynamic> metadata) =>
      {'metadata': metadata};

  static Map<String, dynamic> completeTaskOccurrence({
    required String taskId,
    required String scheduledAt,
    required String? completedAt,
  }) => {
    'taskId': taskId,
    'scheduledAt': scheduledAt,
    'completedAt': completedAt,
  };
}

abstract final class NoteOperationContract {
  /// Returns a human-readable contract error, or null when the operation is
  /// valid for the local editor/outbox seam.
  static String? validate({
    required String kind,
    required String? blockId,
    required Map<String, dynamic> payload,
  }) {
    final parsedKind = NoteOperationKind.tryParse(kind);
    if (parsedKind == null) return 'unknown operation kind: $kind';

    switch (parsedKind) {
      case NoteOperationKind.textDelta:
        if (blockId == null || blockId.isEmpty) {
          return 'blockId is required for text_delta';
        }
        return payload['ops'] is List ? null : 'ops must be a list';
      case NoteOperationKind.createBlock:
        final id = payload['id'];
        if (id is! String || id.isEmpty) {
          return 'id is required for create_block';
        }
        if (blockId != null && blockId != id) {
          return 'blockId must match id for create_block';
        }
        if (payload['type'] is! String || (payload['type'] as String).isEmpty) {
          return 'type is required for create_block';
        }
        if (payload['delta'] is! List) return 'delta must be a list';
        if (payload.containsKey('metadata') &&
            payload['metadata'] != null &&
            payload['metadata'] is! Map) {
          return 'metadata must be an object';
        }
        return _optionalString(payload, 'afterBlockId');
      case NoteOperationKind.deleteBlock:
        return _matchesBlockId(
          blockId,
          payload['blockId'],
          NoteOperationKind.deleteBlock.wireName,
        );
      case NoteOperationKind.moveBlock:
        final blockError = _matchesBlockId(
          blockId,
          payload['blockId'],
          NoteOperationKind.moveBlock.wireName,
        );
        return blockError ?? _optionalString(payload, 'afterBlockId');
      case NoteOperationKind.setBlockType:
        if (blockId == null || blockId.isEmpty) {
          return 'blockId is required for set_block_type';
        }
        final type = payload['type'];
        return type is String && type.isNotEmpty
            ? null
            : 'type is required for set_block_type';
      case NoteOperationKind.setBlockMetadata:
        if (blockId == null || blockId.isEmpty) {
          return 'blockId is required for set_block_metadata';
        }
        return payload['metadata'] is Map ? null : 'metadata must be an object';
      case NoteOperationKind.completeTaskOccurrence:
        if (blockId == null || blockId.isEmpty) {
          return 'blockId is required for complete_task_occurrence';
        }
        final taskId = payload['taskId'];
        if (taskId != blockId) return 'taskId must match blockId';
        final scheduledAt = payload['scheduledAt'];
        if (scheduledAt is! String || scheduledAt.isEmpty) {
          return 'scheduledAt is required';
        }
        final completedAt = payload['completedAt'];
        if (completedAt != null &&
            (completedAt is! String || completedAt.isEmpty)) {
          return 'completedAt must be null or a non-empty string';
        }
        return null;
    }
  }

  static String? _matchesBlockId(
    String? blockId,
    Object? payloadBlockId,
    String kind,
  ) {
    if (blockId == null || blockId.isEmpty) {
      return 'blockId is required for $kind';
    }
    return payloadBlockId == blockId
        ? null
        : 'payload blockId must match blockId for $kind';
  }

  static String? _optionalString(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    return value == null || value is String
        ? null
        : '$key must be null or a string';
  }
}
