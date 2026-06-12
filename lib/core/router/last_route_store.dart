import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/router/app_routes.dart';

class LastRouteStore {
  const LastRouteStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'last_route';

  String initialLocation() {
    final route = _prefs.getString(_key);
    if (route == null || !_isPersistable(route)) {
      return AppRoutes.home;
    }
    return route;
  }

  Future<void> save(String location) async {
    if (!_isPersistable(location)) return;
    await _prefs.setString(_key, location);
  }

  Future<void> clear() => _prefs.remove(_key);

  static bool _isPersistable(String location) {
    if (location == AppRoutes.login || location == AppRoutes.register) {
      return false;
    }
    if (location == AppRoutes.home ||
        location == AppRoutes.inbox ||
        location == AppRoutes.settings ||
        location == AppRoutes.soul ||
        location == AppRoutes.contexts ||
        location == AppRoutes.routines ||
        location == AppRoutes.routinesLogs ||
        location == AppRoutes.telegram ||
        location == AppRoutes.chat ||
        location == AppRoutes.search ||
        location == AppRoutes.memories) {
      return true;
    }
    return location.startsWith('/notes/') && location.length > '/notes/'.length;
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final lastRouteStoreProvider = Provider<LastRouteStore>((ref) {
  return LastRouteStore(ref.watch(sharedPreferencesProvider));
});
