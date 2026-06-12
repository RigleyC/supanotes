import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/router/last_route_store.dart';

void main() {
  group('LastRouteStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns /splash when there is no persisted route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      expect(store.initialLocation(), AppRoutes.splash);
    });

    test('persists and restores a safe note route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save('/notes/note-1');

      expect(store.initialLocation(), '/notes/note-1');
    });

    test('does not persist public auth routes', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save(AppRoutes.login);
      await store.save(AppRoutes.register);
      await store.save(AppRoutes.splash);

      expect(store.initialLocation(), AppRoutes.splash);
    });

    test('persists any non-auth route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save('/unknown');

      expect(store.initialLocation(), '/unknown');
    });

    test('clear removes the persisted route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save(AppRoutes.settings);
      await store.clear();

      expect(store.initialLocation(), AppRoutes.splash);
    });
  });
}
