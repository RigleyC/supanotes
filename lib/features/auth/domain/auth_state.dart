/// Auth state machine — pure domain types only.
///
/// These sealed classes represent the three legitimate auth states.
/// The [AuthController] that drives them lives in
/// `presentation/controllers/auth_controller.dart`.
library;

/// State machine for the current auth session.
///
/// Exposed as a [sealed class] so consumers can exhaustively pattern-match
/// on the three legitimate states (initial / unauthenticated / authenticated)
/// without worrying about a fourth "loading" shape — that concern is owned
/// by Riverpod's [AsyncValue] wrapper around this state.
sealed class AuthState {
  const AuthState();
}

/// The auth provider has not yet checked local storage.
///
/// Rendered briefly at app start; the router does not redirect while
/// this is the current state so we don't bounce the user to /login before
/// we know whether they have a saved session.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// The device has no session (or the session was just revoked by a
/// failed refresh). The router should bounce the user to /login.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// The device has a valid session and we know the user's id, email, and
/// display name. These are all read from the backend response on login /
/// register; the controller does not currently re-fetch the profile.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.email,
    required this.name,
  });

  final String userId;
  final String email;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticated &&
      other.userId == userId &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(userId, email, name);
}
