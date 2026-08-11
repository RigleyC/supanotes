import 'dart:convert';

import 'package:supanotes/features/notes/catalog/model/note_icon.dart';

/// The typed subset of a catalog response needed to hydrate a remote note.
///
/// This model belongs to the catalog boundary. It contains no Drift companion
/// or persistence mapping, so sharing can pass the authenticated result to the
/// catalog without importing its data layer.
final class RemoteNoteMetadata {
  const RemoteNoteMetadata({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    required this.hasCollapseImages,
    required this.collapseImages,
    required this.hasPermission,
    required this.permission,
    required this.hasSharedByEmail,
    required this.sharedByEmail,
    required this.hasSharedByName,
    required this.sharedByName,
    required this.hasNoteIcon,
    required this.noteIcon,
  });

  factory RemoteNoteMetadata.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    return RemoteNoteMetadata(
      id: id,
      userId: _optionalString(json, 'user_id'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      hasCollapseImages: json.containsKey('collapse_images'),
      collapseImages: _optionalBool(json, 'collapse_images'),
      hasPermission: json.containsKey('permission'),
      permission: _optionalString(json, 'permission'),
      hasSharedByEmail: json.containsKey('shared_by_email'),
      sharedByEmail: _optionalString(json, 'shared_by_email'),
      hasSharedByName: json.containsKey('shared_by_name'),
      sharedByName: _optionalString(json, 'shared_by_name'),
      hasNoteIcon: json.containsKey('note_icon'),
      noteIcon: _optionalNoteIcon(json, 'note_icon', noteId: id),
    );
  }

  final String id;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hasCollapseImages;
  final bool? collapseImages;
  final bool hasPermission;
  final String? permission;
  final bool hasSharedByEmail;
  final String? sharedByEmail;
  final bool hasSharedByName;
  final String? sharedByName;
  final bool hasNoteIcon;
  final NoteIcon? noteIcon;

  /// The notes endpoint omits permission for the authenticated owner.
  bool get isOwner => !hasPermission && permission == null;

  bool get hasShareMetadata =>
      hasPermission || hasSharedByEmail || hasSharedByName;

  bool hasShareMetadataFor(String currentUserId) =>
      hasShareMetadata || isOwner || userId == currentUserId;

  String? get noteIconJson =>
      noteIcon == null ? null : jsonEncode(noteIcon!.toJson());
}

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
