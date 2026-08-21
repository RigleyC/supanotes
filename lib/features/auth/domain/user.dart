/// User profile returned by the auth endpoints.
class User {
  const User({required this.id, required this.email, required this.name});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
    );
  }

  final String id;
  final String email;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, email, name);
}

/// Session data returned by the backend on login / register so the
/// client can bootstrap its local cache without extra round-trips.
class SessionData {
  const SessionData({
    required this.settings,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      settings: json['settings'] as Map<String, dynamic>? ?? const {},
    );
  }

  final Map<String, dynamic> settings;
}

/// Result of a successful login or register.
class AuthResult {
  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.session,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      session: SessionData.fromJson(json),
    );
  }

  final User user;
  final String accessToken;
  final String refreshToken;
  final SessionData session;
}
