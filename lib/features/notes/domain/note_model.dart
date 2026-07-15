import '../../../core/database/daos/notes_dao.dart';

class NoteModel {
  const NoteModel({
    required this.id,
    required this.userId,
    this.content,
    required this.title,
    this.excerpt,
    required this.favorite,
    required this.archived,
    required this.contextId,
    required this.createdAt,
    required this.updatedAt,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.permission,
    this.sharedByEmail,
    this.sharedByName,
  });

  final String id;
  final String userId;
  final String? content;
  final String title;
  final String? excerpt;
  final bool favorite;
  final bool archived;
  final String? contextId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hideCompleted;
  final bool collapseImages;
  final String? permission;
  final String? sharedByEmail;
  final String? sharedByName;

  bool get isOwner => permission == null;
  bool get isReadOnly => permission == 'view';
  bool get isShared => sharedByEmail != null;

  NoteModel copyWith({
    String? id,
    String? userId,
    String? content,
    String? title,
    String? excerpt,
    bool? favorite,
    bool? archived,
    String? contextId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hideCompleted,
    bool? collapseImages,
    String? permission,
    String? sharedByEmail,
    String? sharedByName,
  }) => NoteModel(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    content: content ?? this.content,
    title: title ?? this.title,
    excerpt: excerpt ?? this.excerpt,
    favorite: favorite ?? this.favorite,
    archived: archived ?? this.archived,
    contextId: contextId ?? this.contextId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    hideCompleted: hideCompleted ?? this.hideCompleted,
    collapseImages: collapseImages ?? this.collapseImages,
    permission: permission ?? this.permission,
    sharedByEmail: sharedByEmail ?? this.sharedByEmail,
    sharedByName: sharedByName ?? this.sharedByName,
  );

  factory NoteModel.fromQueryResult(NoteQueryResult qr) {
    return NoteModel(
      id: qr.note.id,
      userId: qr.note.userId,
      content: qr.note.content,
      title: qr.title,
      excerpt: qr.note.excerpt,
      favorite: qr.favorite,
      archived: qr.archived,
      contextId: qr.note.contextId,
      createdAt: qr.note.createdAt,
      updatedAt: qr.note.updatedAt,
      hideCompleted: qr.hideCompleted,
      collapseImages: qr.note.collapseImages,
      permission: qr.note.permission?.isNotEmpty == true
          ? qr.note.permission
          : null,
      sharedByEmail: qr.note.sharedByEmail?.isNotEmpty == true
          ? qr.note.sharedByEmail
          : null,
      sharedByName: qr.note.sharedByName?.isNotEmpty == true
          ? qr.note.sharedByName
          : null,
    );
  }
}
