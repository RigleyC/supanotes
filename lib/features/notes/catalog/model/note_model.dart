import 'package:supanotes/core/database/daos/notes_dao.dart';
import 'dart:convert';

import 'note_icon.dart';

class NoteModel {
  const NoteModel({
    required this.id,
    required this.userId,
    this.content,
    required this.title,
    this.excerpt,
    required this.favorite,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    this.hideCompleted = false,
    this.collapseImages = false,
    this.permission,
    this.sharedByEmail,
    this.sharedByName,
    this.noteIcon,
  });

  final String id;
  final String userId;
  final String? content;
  final String title;
  final String? excerpt;
  final bool favorite;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hideCompleted;
  final bool collapseImages;
  final String? permission;
  final String? sharedByEmail;
  final String? sharedByName;
  final NoteIcon? noteIcon;

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
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hideCompleted,
    bool? collapseImages,
    String? permission,
    String? sharedByEmail,
    String? sharedByName,
    NoteIcon? noteIcon,
  }) => NoteModel(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    content: content ?? this.content,
    title: title ?? this.title,
    excerpt: excerpt ?? this.excerpt,
    favorite: favorite ?? this.favorite,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    hideCompleted: hideCompleted ?? this.hideCompleted,
    collapseImages: collapseImages ?? this.collapseImages,
    permission: permission ?? this.permission,
    sharedByEmail: sharedByEmail ?? this.sharedByEmail,
    sharedByName: sharedByName ?? this.sharedByName,
    noteIcon: noteIcon ?? this.noteIcon,
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
      noteIcon: qr.note.noteIconJson == null
          ? null
          : NoteIcon.fromJson(
              jsonDecode(qr.note.noteIconJson!) as Map<String, dynamic>,
            ),
    );
  }
}
