/// Plain Dart models for the Settings/SOUL/Contexts feature.
///
/// These types mirror the JSON shapes returned by the backend handlers
/// in `backend/internal/settings`, `backend/internal/soul`, and
/// `backend/internal/contexts` so the repository layer can `fromJson`
/// into them without leaking `Map<String, dynamic>` to widgets.
library;

/// User-level settings (currently just the IANA timezone).
class UserSettings {
  const UserSettings({
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
  });

  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      timezone: json['timezone'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}

/// The user-editable persona prompt fed to the agent.
class Soul {
  const Soul({required this.personality});

  final String personality;

  factory Soul.fromJson(Map<String, dynamic> json) {
    return Soul(personality: json['personality'] as String? ?? '');
  }
}

/// A user-owned "folder" used to group notes.
class UserContext {
  const UserContext({
    required this.id,
    required this.slug,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String slug;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserContext.fromJson(Map<String, dynamic> json) {
    return UserContext(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}
