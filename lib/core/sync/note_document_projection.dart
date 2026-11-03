import 'dart:convert';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

/// The fully computed local representation of a canonical note snapshot.
///
/// Projection is deliberately performed before the persistence unit starts its
/// write transaction. A malformed snapshot or operation therefore cannot
/// leave a newer canonical document paired with an older materialized view.
final class NoteDocumentProjection {
  const NoteDocumentProjection({
    required this.canonicalJson,
    required this.materializedJson,
    required this.content,
    required this.excerpt,
  });

  final String canonicalJson;
  final String materializedJson;
  final String content;
  final String? excerpt;
}

final class NoteDocumentProjector {
  NoteDocumentProjector();

  final NoteDocumentCodec _codec = const NoteDocumentCodec();

  NoteDocumentProjection project({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData> pendingOperations,
  }) {
    _validateEnvelope(snapshot);
    // A malformed block, in the snapshot or in a pending create, rejects the
    // whole projection before anything is written.
    for (final raw in snapshot['blocks'] as List<dynamic>) {
      if (raw is! Map) {
        throw const FormatException('Note document contains an invalid block');
      }
      _codec.parseBlock(Map<String, dynamic>.from(raw));
    }
    for (final operation in pendingOperations) {
      if (operation.kind != NoteOperationWireNames.createBlock) continue;
      final payload = jsonDecode(operation.payloadJson);
      if (payload is! Map) {
        throw const FormatException('Note operation payload must be an object');
      }
      _codec.parseBlock(Map<String, dynamic>.from(payload));
    }
    final materialized = noteSnapshotFromBlocks(
      projectNoteBlocks(snapshot: snapshot, pendingOps: pendingOperations),
      schemaVersion: snapshot['schemaVersion'] as int? ?? 1,
    );
    final summary = _codec.projectContent(
      materialized['blocks'] as List<dynamic>,
    );
    return NoteDocumentProjection(
      canonicalJson: jsonEncode(snapshot),
      materializedJson: jsonEncode(materialized),
      content: summary.content,
      excerpt: summary.excerpt,
    );
  }

  NoteDocumentProjection projectMaterialized(String documentJson) {
    final decoded = jsonDecode(documentJson);
    if (decoded is! Map) {
      throw const FormatException('Note document must be a JSON object');
    }
    final snapshot = Map<String, dynamic>.from(decoded);
    _validateEnvelope(snapshot);
    final blocks = snapshot['blocks'] as List<dynamic>;
    final summary = _codec.projectContent(blocks);
    return NoteDocumentProjection(
      canonicalJson: documentJson,
      materializedJson: documentJson,
      content: summary.content,
      excerpt: summary.excerpt,
    );
  }

  void _validateEnvelope(Map<String, dynamic> snapshot) {
    final schemaVersion = snapshot['schemaVersion'];
    if (schemaVersion != null && schemaVersion != 1) {
      throw const FormatException(
        'Note document has an unsupported schema version',
      );
    }
    if (snapshot['blocks'] is! List) {
      throw const FormatException('Note document blocks must be a list');
    }
  }
}
