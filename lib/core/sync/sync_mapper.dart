/// Converts between local database rows and the JSON wire format used by
/// the sync API.
///
/// Push direction (toJson):  typed data → Map for the HTTP body.
/// Pull direction (fromJson): raw Map   → typed data for the DAOs.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:supanotes/core/database/database.dart';

String? _nullIfEmpty(String? s) => (s != null && s.isEmpty) ? null : s;

class SyncMapper {
  // ---------------------------------------------------------------------------
  // Push direction — typed → Map
  // ---------------------------------------------------------------------------

  Map<String, dynamic> noteToJson(NoteData n) => {
    'id': n.id,
    'user_id': n.userId,
    'context_id': n.contextId,
    'collapse_images': n.collapseImages,
    'embedding_status': n.embeddingStatus,
    'shared_permission': n.permission ?? '',
    'shared_by_email': n.sharedByEmail ?? '',
    'shared_by_name': n.sharedByName ?? '',
    'created_at': n.createdAt.toUtc().toIso8601String(),
    'updated_at': n.updatedAt.toUtc().toIso8601String(),
    'deleted_at': n.deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, dynamic> contextToJson(ContextData c) => {
    'id': c.id,
    'slug': c.slug,
    'name': c.name,
    'created_at': c.createdAt.toUtc().toIso8601String(),
    'updated_at': c.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> tagToJson(TagData t) => {
    'id': t.id,
    'name': t.name,
    'created_at': t.createdAt.toUtc().toIso8601String(),
    'updated_at': t.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> noteLinkToJson(NoteLinkData l) => {
    'id': l.id,
    'source_id': l.sourceId,
    'target_id': l.targetId,
    'relation': l.relation,
    'created_at': l.createdAt.toUtc().toIso8601String(),
    'updated_at': l.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> localNoteTagToJson(LocalNoteTagData t) => {
    'note_id': t.noteId,
    'tag_id': t.tagId,
  };

  // ---------------------------------------------------------------------------
  // Pull direction — Map → typed
  // ---------------------------------------------------------------------------

  NoteData noteFromJson(Map<String, dynamic> json) => NoteData(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    contextId: json['context_id'] as String?,
    content: json['content'] as String,
    excerpt: json['excerpt'] as String?,
    embeddingStatus: json['embedding_status'] as String?,
    permission: _nullIfEmpty(json['shared_permission'] as String?),
    sharedByEmail: _nullIfEmpty(json['shared_by_email'] as String?),
    sharedByName: _nullIfEmpty(json['shared_by_name'] as String?),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    deletedAt: json['deleted_at'] != null
        ? DateTime.parse(json['deleted_at'] as String).toLocal()
        : null,
    isDirty: false,
    hasRemoteCopy: true,
    collapseImages: (json['collapse_images'] as bool?) ?? false,
  );

  ContextData contextFromJson(Map<String, dynamic> json) => ContextData(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    slug: json['slug'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    isDirty: false,
  );

  TagData tagFromJson(Map<String, dynamic> json) => TagData(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    isDirty: false,
  );

  NoteLinkData noteLinkFromJson(Map<String, dynamic> json) => NoteLinkData(
    id: json['id'] as String,
    sourceId: json['source_id'] as String,
    targetId: json['target_id'] as String,
    relation: (json['relation'] as String?) ?? 'related',
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String).toLocal()
        : DateTime.now(),
    updatedAt: json['updated_at'] != null
        ? DateTime.parse(json['updated_at'] as String).toLocal()
        : DateTime.now(),
    isDirty: false,
  );

  LocalNoteTagData localNoteTagFromJson(Map<String, dynamic> json) =>
      LocalNoteTagData(
        noteId: json['note_id'] as String,
        tagId: json['tag_id'] as String,
        isDirty: false,
      );

  Map<String, dynamic> userNotePreferenceToJson(UserNotePreferenceData p) {
    return {
      'user_id': p.userId,
      'note_id': p.noteId,
      'favorite': p.favorite,
      'archived': p.archived,
      'hide_completed': p.hideCompleted,
      'filters': p.filters,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
    };
  }

  UserNotePreferencesCompanion userNotePreferenceFromJson(
    Map<String, dynamic> json,
  ) {
    return UserNotePreferencesCompanion(
      userId: Value(json['user_id'] as String),
      noteId: Value(json['note_id'] as String),
      favorite: Value(json['favorite'] as bool? ?? false),
      archived: Value(json['archived'] as bool? ?? false),
      hideCompleted: Value(json['hide_completed'] as bool? ?? false),
      filters: Value(json['filters'] as String? ?? '{}'),
      createdAt: Value(DateTime.parse(json['created_at'] as String).toLocal()),
      updatedAt: Value(DateTime.parse(json['updated_at'] as String).toLocal()),
      isDirty: const Value(false),
    );
  }

  Map<String, dynamic> localYjsStateToJson(LocalYjsState s) => {
    'note_id': s.noteId,
    'state': base64Encode(s.state),
    'updated_at': s.updatedAt.toUtc().toIso8601String(),
  };

  LocalYjsState localYjsStateFromJson(Map<String, dynamic> json) {
    return LocalYjsState(
      noteId: json['note_id'] as String,
      state: base64Decode(json['state'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}
