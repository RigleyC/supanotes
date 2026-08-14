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
        return _validateTextDelta(blockId, payload);
      case NoteOperationKind.createBlock:
        return _validateCreateBlock(blockId, payload);
      case NoteOperationKind.deleteBlock:
        return _validateDeleteBlock(blockId, payload);
      case NoteOperationKind.moveBlock:
        return _validateMoveBlock(blockId, payload);
      case NoteOperationKind.setBlockType:
        return _validateSetBlockType(blockId, payload);
      case NoteOperationKind.setBlockMetadata:
        return _validateSetBlockMetadata(blockId, payload);
      case NoteOperationKind.completeTaskOccurrence:
        return _validateCompleteTaskOccurrence(blockId, payload);
    }
  }

  static String? _validateTextDelta(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null || blockId.isEmpty) {
      return 'blockId is required for text_delta';
    }
    final ops = payload['ops'];
    if (ops is! List) return 'ops must be a list';
    return ops.every((op) => op is Map) ? null : 'ops must contain objects';
  }

  static String? _validateCreateBlock(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    final id = payload['id'];
    if (id is! String || id.isEmpty) {
      return 'id is required for create_block';
    }
    if (blockId != null && blockId != id) {
      return 'blockId must match id for create_block';
    }
    final type = payload['type'];
    if (type is! String || type.isEmpty) {
      return 'type is required for create_block';
    }
    if (payload['delta'] is! List) return 'delta must be a list';
    if (payload.containsKey('metadata') &&
        payload['metadata'] != null &&
        payload['metadata'] is! Map) {
      return 'metadata must be an object';
    }
    if (type == 'task') {
      final legacyError = _rejectLegacyTaskMetadata(payload['metadata']);
      if (legacyError != null) return legacyError;
    }
    return _optionalString(payload, 'afterBlockId');
  }

  static String? _validateDeleteBlock(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    return _matchesBlockId(
      blockId,
      payload['blockId'],
      NoteOperationKind.deleteBlock.wireName,
    );
  }

  static String? _validateMoveBlock(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    final blockError = _matchesBlockId(
      blockId,
      payload['blockId'],
      NoteOperationKind.moveBlock.wireName,
    );
    return blockError ?? _optionalString(payload, 'afterBlockId');
  }

  static String? _validateSetBlockType(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null || blockId.isEmpty) {
      return 'blockId is required for set_block_type';
    }
    final type = payload['type'];
    return type is String && type.isNotEmpty
        ? null
        : 'type is required for set_block_type';
  }

  static String? _validateSetBlockMetadata(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null || blockId.isEmpty) {
      return 'blockId is required for set_block_metadata';
    }
    if (payload['metadata'] is! Map) return 'metadata must be an object';
    return _rejectLegacyTaskMetadata(payload['metadata']);
  }

  static String? _rejectLegacyTaskMetadata(Object? rawMetadata) {
    if (rawMetadata is! Map) return null;
    for (final key in const ['checked', 'recurrence']) {
      if (rawMetadata.containsKey(key)) {
        return 'legacy $key metadata is not allowed; run the task document backfill';
      }
    }
    return null;
  }

  static String? _validateCompleteTaskOccurrence(
    String? blockId,
    Map<String, dynamic> payload,
  ) {
    if (blockId == null || blockId.isEmpty) {
      return 'blockId is required for complete_task_occurrence';
    }
    final taskId = payload['taskId'];
    if (taskId != blockId) return 'taskId must match blockId';
    final scheduledAt = payload['scheduledAt'];
    if (scheduledAt is! String || scheduledAt.isEmpty) {
      return 'scheduledAt is required';
    }
    if (!_isCanonicalTimestamp(scheduledAt, _canonicalScheduledAtPattern)) {
      return 'scheduledAt must be a canonical calendar timestamp without an offset';
    }
    final completedAt = payload['completedAt'];
    if (completedAt != null &&
        (completedAt is! String || completedAt.isEmpty)) {
      return 'completedAt must be null or a non-empty string';
    }
    if (completedAt is String &&
        !_isCanonicalTimestamp(completedAt, _canonicalCompletedAtPattern)) {
      return 'completedAt must be a UTC timestamp';
    }
    return null;
  }

  static final _canonicalScheduledAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?$',
  );

  static final _canonicalCompletedAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?Z$',
  );

  static bool _isCanonicalTimestamp(String value, RegExp pattern) {
    final match = pattern.firstMatch(value);
    if (match == null) return false;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final millisecond = int.parse(match.group(7)!);
    final microsecond = int.parse(match.group(8) ?? '0');
    final parsed = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
    return parsed.year == year &&
        parsed.month == month &&
        parsed.day == day &&
        parsed.hour == hour &&
        parsed.minute == minute &&
        parsed.second == second &&
        parsed.millisecond == millisecond &&
        parsed.microsecond == microsecond;
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
