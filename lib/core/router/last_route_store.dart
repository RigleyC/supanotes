import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/router/app_routes.dart';

class LastRouteStore {
  const LastRouteStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'last_route';

  String initialLocation() {
    final route = _prefs.getString(_key);
    debugPrint('[LastRoute] initialLocation read: $route');
    if (route == null || !_isPersistable(route)) {
      debugPrint(
        '[LastRoute] initialLocation -> splash (null or not persistable)',
      );
      return AppRoutes.splash;
    }
    debugPrint('[LastRoute] initialLocation -> $route');
    return route;
  }

  Future<void> save(String location) async {
    debugPrint(
      '[LastRoute] save called with: $location persistable=${_isPersistable(location)}',
    );
    if (!_isPersistable(location)) return;
    await _prefs.setString(_key, location);
    debugPrint('[LastRoute] save completed: $location');
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
