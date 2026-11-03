import 'dart:collection';

import 'package:uuid/uuid.dart';

/// Strict, transport-independent representation of a canonical note
/// snapshot. Sharing and sync envelopes may carry this value, but only this
/// document layer validates and decodes its block contract.
dynamic _freezeJsonValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries)
        entry.key.toString(): _freezeJsonValue(entry.value),
    });
  }
  if (value is List) {
    return UnmodifiableListView<dynamic>(value.map(_freezeJsonValue));
  }
  return value;
}

final class NoteDocumentSnapshot {
  NoteDocumentSnapshot._(List<NoteDocumentBlock> blocks)
    : blocks = UnmodifiableListView<NoteDocumentBlock>(blocks);

  factory NoteDocumentSnapshot.fromJson(Map<String, dynamic> json) =>
      const NoteDocumentCodec().parseSnapshot(json);

  final List<NoteDocumentBlock> blocks;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'blocks': blocks.map((block) => block.toJson()).toList(growable: false),
  };
}

final class NoteDocumentBlock {
  NoteDocumentBlock({
    required this.id,
    required this.type,
    required List<Map<String, dynamic>> delta,
    required Map<String, dynamic> metadata,
  }) : delta = UnmodifiableListView<Map<String, dynamic>>(
         delta.map(
           (operation) => _freezeJsonValue(operation) as Map<String, dynamic>,
         ),
       ),
       metadata = _freezeJsonValue(metadata) as Map<String, dynamic>;

  final String id;
  final String type;
  final List<Map<String, dynamic>> delta;
  final Map<String, dynamic> metadata;

  String get text =>
      delta.map((operation) => operation['insert']).whereType<String>().join();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'delta': delta,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class NoteDocumentCodec {
  const NoteDocumentCodec();

  static const supportedBlockTypes = {
    'paragraph',
    'header1',
    'header2',
    'header3',
    'quote',
    'bulletList',
    'orderedList',
    'task',
    'divider',
    'attachment',
    'rich_link',
  };
  NoteDocumentSnapshot parseSnapshot(
    Map<String, dynamic> json, {
    bool allowEmptyDeltaOperations = false,
    bool allowMutationDeltaOperations = false,
  }) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'Note document has an unsupported schema version',
      );
    }
    final rawBlocks = json['blocks'];
    if (rawBlocks is! List || rawBlocks.isEmpty) {
      throw const FormatException('Note document has no blocks');
    }

    final ids = <String>{};
    final blocks = rawBlocks
        .map((rawBlock) {
          if (rawBlock is! Map) {
            throw const FormatException(
              'Note document contains an invalid block',
            );
          }
          final block = _parseBlock(
            Map<String, dynamic>.from(rawBlock),
            allowEmptyDeltaOperations: allowEmptyDeltaOperations,
            allowMutationDeltaOperations: allowMutationDeltaOperations,
          );
          if (!ids.add(block.id)) {
            throw const FormatException(
              'Note document contains duplicate block ids',
            );
          }
          return block;
        })
        .toList(growable: false);
    return NoteDocumentSnapshot._(blocks);
  }

  NoteDocumentBlock _parseBlock(
    Map<String, dynamic> json, {
    bool allowEmptyDeltaOperations = false,
    bool allowMutationDeltaOperations = false,
  }) {
    final rawId = json['id'];
    final rawType = json['type'];
    _validateBlockIdentity(rawId, rawType);

    final delta = _parseDelta(
      json['delta'],
      allowEmptyDeltaOperations: allowEmptyDeltaOperations,
      allowMutationDeltaOperations: allowMutationDeltaOperations,
    );
    final metadata = _parseMetadata(json['metadata']);
    _validateMetadata(rawType as String, metadata);
    return NoteDocumentBlock(
      id: rawId as String,
      type: rawType,
      delta: delta,
      metadata: metadata,
    );
  }

  void _validateBlockIdentity(dynamic rawId, dynamic rawType) {
    if (rawId is! String || rawId.isEmpty) {
      throw const FormatException('Note document block has no id');
    }
    if (rawType is! String || rawType.isEmpty) {
      throw const FormatException('Note document block has no type');
    }
    if (!supportedBlockTypes.contains(rawType)) {
      throw FormatException('Unsupported note document block type: $rawType');
    }
  }

  List<Map<String, dynamic>> _parseDelta(
    dynamic rawDelta, {
    required bool allowEmptyDeltaOperations,
    required bool allowMutationDeltaOperations,
  }) {
    if (rawDelta is! List) {
      throw const FormatException('Note document block has no delta');
    }
    return rawDelta
        .map<Map<String, dynamic>?>((rawOperation) {
          return _parseDeltaOperation(
            rawOperation,
            allowEmptyDeltaOperations: allowEmptyDeltaOperations,
            allowMutationDeltaOperations: allowMutationDeltaOperations,
          );
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Map<String, dynamic>? _parseDeltaOperation(
    dynamic rawOperation, {
    required bool allowEmptyDeltaOperations,
    required bool allowMutationDeltaOperations,
  }) {
    if (rawOperation is! Map) {
      throw const FormatException(
        'Note document block contains an invalid delta',
      );
    }
    final operation = Map<String, dynamic>.from(rawOperation);
    if (allowEmptyDeltaOperations && operation.isEmpty) {
      return <String, dynamic>{'insert': ''};
    }
    if (operation['insert'] is! String) {
      if (allowMutationDeltaOperations && _isMutationOperation(operation)) {
        return null;
      }
      throw const FormatException(
        'Note document block contains a non-text delta operation',
      );
    }
    _validateDeltaAttributes(operation['attributes']);
    return operation;
  }

  bool _isMutationOperation(Map<String, dynamic> operation) {
    return !operation.containsKey('insert') &&
        (operation['delete'] is int || operation['retain'] is int);
  }

  void _validateDeltaAttributes(dynamic rawAttributes) {
    if (rawAttributes != null && rawAttributes is! Map) {
      throw const FormatException(
        'Note document block contains invalid delta attributes',
      );
    }
    if (rawAttributes is! Map) return;

    for (final entry in rawAttributes.entries) {
      _validateDeltaAttributeEntry(entry);
    }
  }

  void _validateDeltaAttributeEntry(MapEntry<dynamic, dynamic> entry) {
    if (entry.key is! String) {
      throw const FormatException(
        'Note document block contains invalid delta attribute names',
      );
    }

    final key = entry.key as String;
    if (key == 'link') {
      _validateLinkAttribute(entry.value);
    } else if (key.startsWith('link:')) {
      _validateLinkAttribution(key, entry.value);
    }
  }

  void _validateLinkAttribute(dynamic value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null) {
      throw const FormatException(
        'Note document block contains an invalid link attribute',
      );
    }
  }

  void _validateLinkAttribution(String key, dynamic value) {
    if (value != true || Uri.tryParse(key.substring(5)) == null) {
      throw const FormatException(
        'Note document block contains an invalid link attribution',
      );
    }
  }

  Map<String, dynamic> _parseMetadata(dynamic rawMetadata) {
    if (rawMetadata != null && rawMetadata is! Map) {
      throw const FormatException('Note document block has invalid metadata');
    }
    return rawMetadata == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(rawMetadata as Map);
  }

  static void _validateMetadata(String type, Map<String, dynamic> metadata) {
    void requireType(String key, bool condition) {
      if (metadata[key] != null && !condition) {
        throw FormatException('Invalid $key metadata for $type block');
      }
    }

    switch (type) {
      case 'rich_link':
        for (final key in const [
          'url',
          'title',
          'description',
          'imageUrl',
          'domain',
          'previewStatus',
          'faviconUrl',
          'siteName',
        ]) {
          requireType(key, metadata[key] is String);
        }
      case 'task':
        for (final key in const ['checked', 'recurrence']) {
          if (metadata.containsKey(key)) {
            throw FormatException(
              'Legacy $key metadata is not allowed; run the task document backfill',
            );
          }
        }
        requireType('isCompleted', metadata['isCompleted'] is bool);
        requireType('indent', metadata['indent'] is int);
        for (final key in const ['dueDate', 'recurrenceRule', 'reminder']) {
          requireType(key, metadata[key] is String);
        }
        requireType('hasTime', metadata['hasTime'] is bool);
        requireType('lastCompletedAt', metadata['lastCompletedAt'] is String);
        requireType('completions', metadata['completions'] is Map);
        requireType(
          'completionHistory',
          metadata['completionHistory'] is List,
        );

        final dueDate = metadata['dueDate'];
        if (dueDate is String && !_isCanonicalScheduledAt(dueDate)) {
          throw const FormatException(
            'Invalid dueDate metadata for task block: expected a canonical calendar timestamp without an offset',
          );
        }

        final recurrenceRule = metadata['recurrenceRule'];
        if (recurrenceRule is String &&
            !_canonicalRecurrenceRules.contains(recurrenceRule)) {
          throw const FormatException(
            'Invalid recurrenceRule metadata for task block',
          );
        }

        final reminder = metadata['reminder'];
        if (reminder is String && !_canonicalReminders.contains(reminder)) {
          throw const FormatException(
            'Invalid reminder metadata for task block',
          );
        }

        final lastCompletedAt = metadata['lastCompletedAt'];
        if (lastCompletedAt is String &&
            !_isCanonicalCompletedAt(lastCompletedAt)) {
          throw const FormatException(
            'Invalid lastCompletedAt metadata for task block: expected a UTC timestamp',
          );
        }

        final completions = metadata['completions'];
        if (completions is Map) {
          for (final entry in completions.entries) {
            if (entry.key is! String || entry.value is! String) {
              throw const FormatException(
                'Invalid completions metadata for task block',
              );
            }
            if (!_isCanonicalScheduledAt(entry.key as String) ||
                !_isCanonicalCompletedAt(entry.value as String)) {
              throw const FormatException(
                'Invalid completions metadata for task block',
              );
            }
          }
        }
        final completionHistory = metadata['completionHistory'];
        if (completionHistory is List) {
          for (final entry in completionHistory) {
            if (entry is! Map ||
                (entry['scheduledAt'] != null &&
                    entry['scheduledAt'] is! String) ||
                entry['hasTime'] is! bool ||
                entry['completedAt'] is! String) {
              throw const FormatException(
                'Invalid archived completion metadata for task block',
              );
            }
            final scheduledAt = entry['scheduledAt'];
            if ((scheduledAt is String &&
                    !_isCanonicalScheduledAt(scheduledAt)) ||
                !_isCanonicalCompletedAt(entry['completedAt'] as String)) {
              throw const FormatException(
                'Invalid archived completion metadata for task block',
              );
            }
          }
        }
      case 'bulletList' || 'orderedList':
        requireType('indent', metadata['indent'] is int);
      case 'attachment':
        for (final key in const [
          'attachmentId',
          'filename',
          'mimeType',
          'url',
        ]) {
          requireType(key, metadata[key] is String);
        }
        requireType('fileSize', metadata['fileSize'] is int);
    }
  }

  static const _canonicalRecurrenceRules = {
    'daily',
    'weekdays',
    'weekly',
    'monthly',
  };

  static const _canonicalReminders = {
    'at_time',
    '5m_before',
    '1h_before',
    '1d_before',
    '9am',
    '12pm',
    '6pm',
    '1d_before_9am',
  };

  static final _canonicalScheduledAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?$',
  );

  static final _canonicalCompletedAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?Z$',
  );

  static bool _isCanonicalScheduledAt(String value) {
    return _isCanonicalTimestamp(value, _canonicalScheduledAtPattern);
  }

  static bool _isCanonicalCompletedAt(String value) {
    return _isCanonicalTimestamp(value, _canonicalCompletedAtPattern);
  }

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

  /// Validates one block as the sync layer receives it, in a snapshot or a
  /// `create_block` payload; throws a [FormatException] when it breaks the
  /// document contract. Blocks created offline may omit their id or use the
  /// legacy `content` key.
  ///
  /// [allowMutationDeltaOperations] drops leaked `retain`/`delete` ops from a
  /// locally persisted block instead of rejecting it.
  NoteDocumentBlock parseBlock(
    Map<String, dynamic> json, {
    bool allowMutationDeltaOperations = false,
  }) {
    final normalized = Map<String, dynamic>.from(json);
    normalized['id'] ??= const Uuid().v4();
    if (normalized['delta'] == null && normalized['content'] is List) {
      normalized['delta'] = normalized['content'];
    }
    return _parseBlock(
      normalized,
      allowEmptyDeltaOperations: true,
      allowMutationDeltaOperations: allowMutationDeltaOperations,
    );
  }

  /// The note's plain text (one line per text block) and its list excerpt.
  ({String content, String? excerpt}) projectContent(List<dynamic> blocks) {
    final text = StringBuffer();
    for (final block in blocks) {
      if (block is! Map) continue;
      final rawDelta = block['delta'] ?? block['content'];
      if (rawDelta is! List) continue;
      final plain = rawDelta
          .map((op) => op is Map ? op['insert'] : null)
          .whereType<String>()
          .join();
      if (plain.isNotEmpty) text.writeln(plain);
    }
    final content = text.toString().trimRight();
    return (
      content: content,
      excerpt: content.isEmpty
          ? null
          : content.substring(0, content.length > 200 ? 200 : content.length),
    );
  }
}
