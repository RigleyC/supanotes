/// Converts between local database rows and the JSON wire format used by
/// the sync API.
///
/// Push direction (toJson):  typed data → Map for the HTTP body.
/// Pull direction (fromJson): raw Map   → typed data for the DAOs.
library;

import 'package:supanotes/core/database/database.dart';

class SyncMapper {
  // ---------------------------------------------------------------------------
  // Push direction — typed → Map
  // ---------------------------------------------------------------------------

  Map<String, dynamic> noteToJson(NoteData n) => {
        'id': n.id,
        'context_id': n.contextId,
        'title': n.title,
        'content': n.content,
        'excerpt': n.excerpt,
        'is_inbox': n.isInbox,
        'favorite': n.favorite,
        'archived': n.archived,
        'embedding_status': n.embeddingStatus,
        'created_at': n.createdAt.toUtc().toIso8601String(),
        'updated_at': n.updatedAt.toUtc().toIso8601String(),
        'deleted_at': n.deletedAt?.toUtc().toIso8601String(),
      };

  Map<String, dynamic> taskToJson(TaskData t) => {
        'id': t.id,
        'note_id': t.noteId,
        'title': t.title,
        'status': t.status,
        'position': t.position,
        'recurrence': t.recurrence,
        'due_date': t.dueDate?.toUtc().toIso8601String(),
        'completed_at': t.completedAt?.toUtc().toIso8601String(),
        'created_at': t.createdAt.toUtc().toIso8601String(),
        'updated_at': t.updatedAt.toUtc().toIso8601String(),
        'deleted_at': t.deletedAt?.toUtc().toIso8601String(),
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

  Map<String, dynamic> taskCompletionToJson(LocalTaskCompletionData c) => {
        'id': c.id,
        'task_id': c.taskId,
        'completed_at': c.completedAt.toUtc().toIso8601String(),
      };

  // ---------------------------------------------------------------------------
  // Pull direction — Map → typed
  // ---------------------------------------------------------------------------

  NoteData noteFromJson(Map<String, dynamic> json) => NoteData(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        contextId: json['context_id'] as String?,
        title: json['title'] as String?,
        content: json['content'] as String,
        excerpt: json['excerpt'] as String?,
        isInbox: (json['is_inbox'] as bool?) ?? false,
        favorite: (json['favorite'] as bool?) ?? false,
        archived: (json['archived'] as bool?) ?? false,
        embeddingStatus: json['embedding_status'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String).toLocal()
            : null,
        isDirty: false,
      );

  TaskData taskFromJson(Map<String, dynamic> json) => TaskData(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        noteId: json['note_id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        position: (json['position'] as int?) ?? 0,
        recurrence: json['recurrence'] as String?,
        dueDate: json['due_date'] != null
            ? DateTime.parse(json['due_date'] as String).toLocal()
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String).toLocal()
            : null,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String).toLocal()
            : null,
        isDirty: false,
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
}
