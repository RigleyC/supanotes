/// In-memory session manager for the agent chat.
///
/// The backend identifies a chat session with a client-generated UUID
/// that is sent in every `POST /api/v1/agent/chat` body and as the
/// `session_id` query parameter on `GET/DELETE /api/v1/agent/messages`.
/// The UUID is created on first access, held in memory only (no
/// persistent storage — restarting the app starts a fresh session), and
/// rotated when the user explicitly taps "Nova conversa" in the AppBar.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final Uuid _uuid = Uuid();

class SessionManager extends Notifier<String> {
  @override
  String build() => _uuid.v4();

  /// Rotates to a brand-new session id, dropping the in-memory pointer
  /// to the previous one. The chat controller watches this provider and
  /// will reload history for the new session automatically.
  void newSession() {
    state = _uuid.v4();
  }
}

final sessionManagerProvider = NotifierProvider<SessionManager, String>(
  SessionManager.new,
);
