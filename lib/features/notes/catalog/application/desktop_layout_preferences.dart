import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/di/providers.dart';

const desktopSidebarWidthPreferenceKey = 'desktop_sidebar_width';

/// Persists desktop-only layout preferences without coupling widgets to the
/// storage implementation.
class DesktopLayoutPreferences {
  final SharedPreferences _preferences;

  const DesktopLayoutPreferences(this._preferences);

  double? get sidebarWidth =>
      _preferences.getDouble(desktopSidebarWidthPreferenceKey);

  Future<void> saveSidebarWidth(double width) =>
      _preferences.setDouble(desktopSidebarWidthPreferenceKey, width);
}

final desktopLayoutPreferencesProvider =
    Provider.autoDispose<DesktopLayoutPreferences>((ref) {
      return DesktopLayoutPreferences(ref.watch(sharedPreferencesProvider));
    });
