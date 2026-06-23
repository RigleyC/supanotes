import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

final soulProvider = FutureProvider.autoDispose<Soul>((ref) async {
  final cache = ref.read(sessionCacheProvider);
  if (cache.soul.isNotEmpty) {
    return Soul(personality: cache.soul['personality'] as String? ?? '');
  }
  return ref.read(settingsRepositoryProvider).getSoul();
});

final soulSaveProvider = AsyncNotifierProvider<SoulSaveNotifier, void>(SoulSaveNotifier.new);

class SoulSaveNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> save(String personality) async {
    state = const AsyncValue.loading();
    try {
      final soul = await ref.read(settingsRepositoryProvider).updateSoul(personality);
      await ref.read(sessionCacheProvider.notifier).updateSoul({
        'personality': soul.personality,
      });
      ref.invalidate(soulProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
