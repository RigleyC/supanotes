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
      final json = raw;
      final id = json['id'] as String;
      final existing = await _database.notesDao.getNoteById(id);
      final createdAt = DateTime.parse(json['created_at'] as String).toUtc();
      final updatedAt = DateTime.parse(json['updated_at'] as String).toUtc();
      if (existing != null &&
          (existing.isDirty || !updatedAt.isAfter(existing.updatedAt))) {
        continue;
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
                hasRemoteCopy: const Value(true),
                collapseImages: Value(
                  json['collapse_images'] as bool? ?? false,
                ),
              ),
            );
      }

      final remote = await _operationsApi.getDocument(id);
      final blocks = remote.document['blocks'] as List<dynamic>? ?? const [];
      final nodes = blocks
          .whereType<Map>()
          .map((block) => codec.decodeNode(Map<String, dynamic>.from(block)))
          .toList();
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
    }
    dev.log('[NoteCatalogSync] Pulled ${rows.length} remote notes');
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
    await sync.pullRemoteNotes(user.id);
    yield null;
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});
