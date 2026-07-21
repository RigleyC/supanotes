/// Plain Dart models for the Settings feature.
///
/// These types mirror the JSON shapes returned by the backend handlers
/// so the repository layer can `fromJson` into them without leaking
/// `Map<String, dynamic>` to widgets.
library;

/// User-level settings (timezone, preferences, timestamps).
class UserSettings {
  const UserSettings({
    required this.timezone,
    required this.preferences,
    required this.createdAt,
    required this.updatedAt,
  });

  final String timezone;
  final Map<String, dynamic> preferences;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      timezone: json['timezone'] as String,
      preferences: json['preferences'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}


