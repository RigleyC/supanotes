import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class SoulState {
  final Soul soul;
  final bool isSaving;
  final bool saveSuccess;
  final Object? saveError;

  const SoulState({
    required this.soul,
    this.isSaving = false,
    this.saveSuccess = false,
    this.saveError,
  });

  SoulState copyWith({
    Soul? soul,
    bool? isSaving,
    bool? saveSuccess,
    Object? saveError,
  }) {
    return SoulState(
      soul: soul ?? this.soul,
      isSaving: isSaving ?? this.isSaving,
      saveSuccess: saveSuccess ?? this.saveSuccess,
      saveError: saveError,
    );
  }
}

final soulProvider =
    AsyncNotifierProvider.autoDispose<SoulNotifier, SoulState>(SoulNotifier.new);

class SoulNotifier extends AsyncNotifier<SoulState> {
  @override
  Future<SoulState> build() async {
    ref.watch(sessionResetProvider);
    final cache = ref.read(sessionCacheProvider);
    final Soul soul;
    if (cache.soul.isNotEmpty) {
      soul = Soul(personality: cache.soul['personality'] as String? ?? '');
    } else {
      soul = await ref.read(settingsRepositoryProvider).getSoul();
    }
    return SoulState(soul: soul);
  }

  Future<void> save(String personality) async {
    final previousState = state.value;
    if (previousState == null) return;

    state = AsyncValue.data(previousState.copyWith(
      isSaving: true,
      saveSuccess: false,
      saveError: null,
    ));

    try {
      final soul = await ref.read(settingsRepositoryProvider).updateSoul(personality);
      await ref.read(sessionCacheProvider.notifier).updateSoul({
        'personality': soul.personality,
      });
      state = AsyncValue.data(SoulState(
        soul: soul,
        isSaving: false,
        saveSuccess: true,
      ));
    } catch (e) {
      state = AsyncValue.data(previousState.copyWith(
        isSaving: false,
        saveError: e,
      ));
    }
  }
}
