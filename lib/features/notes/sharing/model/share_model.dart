import 'share_permission.dart';

class ShareModel {
  final String id;
  final String noteId;
  final String userId;
  final String email;
  final String name;
  final SharePermission permission;

  const ShareModel({
    required this.id,
    required this.noteId,
    required this.userId,
    required this.email,
    required this.name,
    required this.permission,
  });

  factory ShareModel.fromJson(Map<String, dynamic> json) => ShareModel(
    id: json['id'] as String,
    noteId: json['note_id'] as String,
    userId: json['user_id'] as String,
    email: json['email'] as String,
    name: (json['name'] as String?) ?? '',
    permission: SharePermission.fromJson(json['permission'] as String),
  );
}
