import '../../../core/database/database.dart';

/// Immutable view-model for a note shown in the presentation layer.
///
/// The Drift-generated [NoteData] is the source of truth in the local
/// database; [NoteModel] is a hand-rolled facade that hides Drift-specific
/// fields (e.g. `isDirty`, `embeddingStatus`) which the UI has no business
/// reading. The conversion is one-way — there is no `toData()` because
/// mutations always go through the repository, which knows how to bump
/// `updatedAt` and flip the dirty flag.
class NoteModel {
  const NoteModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.isInbox,
    required this.favorite,
    required this.archived,
    required this.contextId,
    required this.createdAt,
    required this.updatedAt,
    this.hideCompleted = false,
  });

  final String id;
  final String userId;
  final String? title;
  final String? excerpt;
  final String content;
  final bool isInbox;
  final bool favorite;
  final bool archived;
  final String? contextId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hideCompleted;

  NoteModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? excerpt,
    String? content,
    bool? isInbox,
    bool? favorite,
    bool? archived,
    String? contextId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hideCompleted,
  }) =>
      NoteModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        excerpt: excerpt ?? this.excerpt,
        content: content ?? this.content,
        isInbox: isInbox ?? this.isInbox,
        favorite: favorite ?? this.favorite,
        archived: archived ?? this.archived,
        contextId: contextId ?? this.contextId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        hideCompleted: hideCompleted ?? this.hideCompleted,
      );

  /// Builds a presentation-layer [NoteModel] from a Drift row. Centralised
  /// here so the rest of the app never has to know about [NoteData].
  factory NoteModel.fromData(NoteData d) {
    return NoteModel(
      id: d.id,
      userId: d.userId,
      title: d.title,
      excerpt: d.excerpt,
      content: d.content,
      isInbox: d.isInbox,
      favorite: d.favorite,
      archived: d.archived,
      contextId: d.contextId,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      hideCompleted: d.hideCompleted,
    );
  }
}
