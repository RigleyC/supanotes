class NoteNode {
  final String id;
  final String noteId;
  final String? parentId;
  final String position;
  final String type;
  final String data;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const NoteNode({
    required this.id,
    required this.noteId,
    this.parentId,
    this.position = 'a0',
    required this.type,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  NoteNode copyWith({
    String? id,
    String? noteId,
    String? parentId,
    String? position,
    String? type,
    String? data,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return NoteNode(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      parentId: parentId ?? this.parentId,
      position: position ?? this.position,
      type: type ?? this.type,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
