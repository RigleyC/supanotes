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
      return AppRoutes.splash;
    }
    return route;
  }

  Future<void> save(String location) async {
    if (!_isPersistable(location)) return;
    await _prefs.setString(_key, location);
  }

  Future<void> clear() => _prefs.remove(_key);

  static bool _isPersistable(String location) =>
      location != AppRoutes.login &&
      location != AppRoutes.register &&
      location != AppRoutes.splash;
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final lastRouteStoreProvider = Provider<LastRouteStore>((ref) {
  return LastRouteStore(ref.watch(sharedPreferencesProvider));
});
