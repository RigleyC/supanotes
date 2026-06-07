import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class SettingsState {
  final String timezone;
  final bool pushEnabled;
  final bool isLoading;

  const SettingsState({
    this.timezone = 'UTC',
    this.pushEnabled = false,
    this.isLoading = false,
  });

  SettingsState copyWith({
    String? timezone,
    bool? pushEnabled,
    bool? isLoading,
  }) =>
      SettingsState(
        timezone: timezone ?? this.timezone,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        isLoading: isLoading ?? this.isLoading,
      );
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    try {
      final settings = await ref.read(settingsRepositoryProvider).getSettings();
      return SettingsState(timezone: settings.timezone);
    } catch (e) {
      return const SettingsState();
    }
  }

  Future<void> load() async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final settings = await ref.read(settingsRepositoryProvider).getSettings();
      state = AsyncValue.data(
        SettingsState(timezone: settings.timezone, isLoading: false),
      );
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(isLoading: false));
    }
  }

  Future<void> updateTimezone(String tz) async {
    await ref.read(settingsRepositoryProvider).updateSettings(tz);
    state = AsyncValue.data(state.value!.copyWith(timezone: tz));
  }

  Future<void> togglePush() async {
    // Will be implemented when settings_screen is refactored
  }

  Future<void> logout() async {
    await ref.read(authControllerProvider.notifier).logout();
  }
}
