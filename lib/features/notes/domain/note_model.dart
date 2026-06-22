import 'package:supanotes/features/notes/domain/note_display_text.dart';
import '../../../core/database/database.dart';

class NoteModel {
  const NoteModel({
    required this.id,
    required this.userId,
    required this.content,
    required this.isInbox,
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
  final String content;
  final bool isInbox;
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

  String get title => deriveNoteTitle(content);
  String? get excerpt => deriveNoteExcerpt(content);

  bool get isOwner => permission == null;
  bool get isReadOnly => permission == 'view';
  bool get isShared => sharedByEmail != null;

  NoteModel copyWith({
    String? id,
    String? userId,
    String? content,
    bool? isInbox,
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
  }) =>
      NoteModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        content: content ?? this.content,
        isInbox: isInbox ?? this.isInbox,
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

  factory NoteModel.fromData(NoteData d, {bool hideCompleted = false}) {
    return NoteModel(
      id: d.id,
      userId: d.userId,
      content: d.content,
      isInbox: d.isInbox,
      favorite: d.favorite,
      archived: d.archived,
      contextId: d.contextId,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      hideCompleted: hideCompleted,
      collapseImages: d.collapseImages,
      permission: d.permission?.isNotEmpty == true ? d.permission : null,
      sharedByEmail: d.sharedByEmail?.isNotEmpty == true ? d.sharedByEmail : null,
      sharedByName: d.sharedByName?.isNotEmpty == true ? d.sharedByName : null,
    );
  }
}
