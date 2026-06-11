library;

class MemoryModel {
  const MemoryModel({
    required this.id,
    required this.content,
    required this.contextSlug,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String content;
  final String? contextSlug;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      id: (json['id'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      contextSlug: json['context_slug'] as String?,
      createdAt: DateTime.tryParse((json['created_at'] ?? '') as String) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}
