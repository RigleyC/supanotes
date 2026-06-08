/// Auth state machine — pure domain types only.
///
/// These sealed classes represent the two legitimate auth states.
/// The [AuthController] that drives them lives in
/// `presentation/controllers/auth_controller.dart`.
library;

import 'user.dart';

/// State machine for the current auth session.
///
/// Exposed as a [sealed class] so consumers can exhaustively pattern-match
/// on the two legitimate states (unauthenticated / authenticated) without
/// worrying about a third "loading" shape — that concern is owned by
/// Riverpod's [AsyncValue] wrapper around this state.
sealed class AuthState {
  const AuthState();
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
  const AuthAuthenticated(this.user);

  final User user;

  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticated && other.user == user;

  @override
  int get hashCode => user.hashCode;
}
