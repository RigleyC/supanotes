import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/note_operations_api.dart';
import 'package:supanotes/features/notes/domain/ot_document_codec.dart';
import 'package:supanotes/features/notes/domain/ot_local_projection.dart';

class NoteCatalogSync {
  NoteCatalogSync({
    required NoteOperationsApiClient operationsApi,
    required AppDatabase database,
  }) : _operationsApi = operationsApi,
       _database = database;

  final NoteOperationsApiClient _operationsApi;
  final AppDatabase _database;

  Future<void> pullRemoteNotes(String userId) async {
    final rows = await _operationsApi.listNotes();
    final projection = OtLocalProjection(database: _database, userId: userId);
    final codec = OtDocumentCodec();

    for (final raw in rows) {
      try {
        await _pullRemoteNote(
          userId: userId,
          json: raw,
          projection: projection,
          codec: codec,
        );
      } catch (error, stackTrace) {
        dev.log(
          '[NoteCatalogSync] Failed to hydrate ${raw['id']}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    dev.log('[NoteCatalogSync] Pulled ${rows.length} remote notes');
  }

  Future<void> _pullRemoteNote({
    required String userId,
    required Map<String, dynamic> json,
    required OtLocalProjection projection,
    required OtDocumentCodec codec,
  }) async {
    final id = json['id'] as String;
    final existing = await _database.notesDao.getNoteById(id);
    final localDocument = await (_database.select(
      _database.localNoteDocuments,
    )..where((document) => document.noteId.equals(id))).getSingleOrNull();
    final createdAt = DateTime.parse(json['created_at'] as String).toUtc();
    final updatedAt = DateTime.parse(json['updated_at'] as String).toUtc();

    if (existing != null &&
        (existing.isDirty ||
            (existing.hasRemoteCopy &&
                localDocument != null &&
                !updatedAt.isAfter(existing.updatedAt)))) {
      return;
    }

    if (existing == null) {
      await _database
          .into(_database.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              userId: userId,
              content: '',
              createdAt: createdAt,
              updatedAt: updatedAt,
              isDirty: const Value(false),
              // This is only a projection target. It must be retried until the
              // remote document is decoded and stored locally.
              hasRemoteCopy: const Value(false),
              collapseImages: Value(json['collapse_images'] as bool? ?? false),
            ),
          );
    }

    final remote = await _operationsApi.getDocument(id);
    final blocks = remote.document['blocks'] as List<dynamic>? ?? const [];
    final nodes = blocks
        .whereType<Map>()
        .map((block) => codec.decodeNode(Map<String, dynamic>.from(block)))
        .toList();
    await _database.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: remote.noteId,
        revision: remote.revision,
        documentJson: jsonEncode(remote.document),
        updatedAt: remote.serverTime,
      ),
    );
    await projection.project(id, MutableDocument(nodes: nodes));
    await (_database.update(
      _database.notes,
    )..where((note) => note.id.equals(id))).write(
      NotesCompanion(
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        isDirty: const Value(false),
        hasRemoteCopy: const Value(true),
        collapseImages: Value(json['collapse_images'] as bool? ?? false),
      ),
    );
    dev.log('[NoteCatalogSync] Hydrated $id with ${nodes.length} blocks');
  }
}

final noteCatalogSyncProvider = StreamProvider.autoDispose<void>((ref) async* {
  final user = ref.watch(authControllerProvider).asData?.value;
  if (user == null) return;

  final sync = NoteCatalogSync(
    operationsApi: ref.watch(noteOperationsApiClientProvider),
    database: ref.watch(appDatabaseProvider),
  );
  while (true) {
    try {
      await sync.pullRemoteNotes(user.id);
      yield null;
    } catch (error, stackTrace) {
      dev.log(
        '[NoteCatalogSync] Pull failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});
