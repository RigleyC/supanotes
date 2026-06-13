/// In-memory cache for the session bootstrap data returned by the backend
/// on login / register.
///
/// The cache is populated by the [AuthController] after a successful auth
/// flow and persisted to disk via [AuthLocalStorage] so it survives app
/// restarts. UI controllers (settings, soul, contexts, routines) read from
/// this cache for their initial state, eliminating the cold-start GETs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_local_storage.dart';

/// The cached subset of the session payload that is small enough to keep
/// in memory and on secure storage.
class SessionCache {
  const SessionCache({
    this.settings = const {},
    this.soul = const {},
    this.contexts = const [],
    this.routines = const [],
  });

  final Map<String, dynamic> settings;
  final Map<String, dynamic> soul;
  final List<dynamic> contexts;
  final List<dynamic> routines;

  bool get isEmpty =>
      settings.isEmpty && soul.isEmpty && contexts.isEmpty && routines.isEmpty;

  factory SessionCache.fromJson(Map<String, dynamic> json) {
    return SessionCache(
      settings: json['settings'] as Map<String, dynamic>? ?? const {},
      soul: json['soul'] as Map<String, dynamic>? ?? const {},
      contexts: json['contexts'] as List<dynamic>? ?? const [],
      routines: json['routines'] as List<dynamic>? ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'settings': settings,
        'soul': soul,
        'contexts': contexts,
        'routines': routines,
      };
}

class SessionCacheNotifier extends Notifier<SessionCache> {
  late final AuthLocalStorage _storage;

  @override
  SessionCache build() {
    _storage = ref.read(authLocalStorageProvider);
    return const SessionCache();
  }

  /// Loads the cache from disk (used on app cold-start).
  Future<void> restore() async {
    final data = await _storage.getSessionData();
    if (data.isNotEmpty) {
      state = SessionCache.fromJson(data);
    }
  }

  /// Saves the raw bootstrap payload from the auth response.
  Future<void> hydrate(Map<String, dynamic> data) async {
    state = SessionCache.fromJson(data);
    await _storage.saveSessionData(data);
  }

  void clear() {
    state = const SessionCache();
  }
}

final sessionCacheProvider =
    NotifierProvider<SessionCacheNotifier, SessionCache>(
  SessionCacheNotifier.new,
);
