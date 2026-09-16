import 'dart:convert';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/editor/document/effective_document_projector.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';

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
  NoteDocumentProjector({EffectiveDocumentProjector? effectiveProjector})
    : _effectiveProjector = effectiveProjector ?? EffectiveDocumentProjector();

  final EffectiveDocumentProjector _effectiveProjector;
  final NoteDocumentCodec _codec = const NoteDocumentCodec();

  NoteDocumentProjection project({
    required Map<String, dynamic> snapshot,
    required List<PendingNoteOperationData> pendingOperations,
  }) {
    _validateEnvelope(snapshot);
    final materialized = _effectiveProjector.project(
      snapshot: snapshot,
      pendingOps: pendingOperations,
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
