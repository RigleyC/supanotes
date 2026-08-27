import 'dart:convert';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';

enum RemoteNoteAccess { owner, edit, view }

/// The typed subset of a catalog response needed to hydrate a remote note.
///
/// This model belongs to the catalog boundary. It contains no Drift companion
/// or persistence mapping, so sharing can pass the authenticated result to the
/// catalog without importing its data layer.
final class RemoteNoteMetadata {
  const RemoteNoteMetadata({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.favorite = false,
    this.archived = false,
    this.hideCompleted = false,
    required this.collapseImages,
    required this.access,
    required this.sharedByEmail,
    required this.sharedByName,
    required this.noteIcon,
  });

  factory RemoteNoteMetadata.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    return RemoteNoteMetadata(
      id: id,
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      favorite: _optionalBool(json, 'favorite') ?? false,
      archived: _optionalBool(json, 'archived') ?? false,
      hideCompleted: _optionalBool(json, 'hide_completed') ?? false,
      collapseImages: _optionalBool(json, 'collapse_images') ?? false,
      access: _parseAccess(_optionalString(json, 'permission')),
      sharedByEmail: _optionalString(json, 'shared_by_email'),
      sharedByName: _optionalString(json, 'shared_by_name'),
      noteIcon: _optionalNoteIcon(json, 'note_icon', noteId: id),
    );
  }

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool favorite;
  final bool archived;
  final bool hideCompleted;
  final bool collapseImages;
  final RemoteNoteAccess access;
  final String? sharedByEmail;
  final String? sharedByName;
  final NoteIcon? noteIcon;

  bool get isOwner => access == RemoteNoteAccess.owner;

  String? get noteIconJson =>
      noteIcon == null ? null : jsonEncode(noteIcon!.toJson());
}

RemoteNoteAccess _parseAccess(String? permission) => switch (permission) {
  null || 'owner' => RemoteNoteAccess.owner,
  'edit' => RemoteNoteAccess.edit,
  'view' => RemoteNoteAccess.view,
  _ => throw FormatException(
    'Unsupported remote note permission "$permission"',
  ),
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Remote note field "$key" must be a non-empty string');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Remote note field "$key" must be a string or null');
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Remote note field "$key" must be a boolean or null');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Remote note field "$key" must be an ISO date');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException catch (error) {
    throw FormatException('Remote note field "$key" is invalid: $error');
  }
}

NoteIcon? _optionalNoteIcon(
  Map<String, dynamic> json,
  String key, {
  required String noteId,
}) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Remote note icon for "$noteId" must be an object');
  }
  try {
    return NoteIcon.fromJson(Map<String, dynamic>.from(value));
  } on Object catch (error) {
    throw FormatException('Remote note icon for "$noteId" is invalid: $error');
  }
}
