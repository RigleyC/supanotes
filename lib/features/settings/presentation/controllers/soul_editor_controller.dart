import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

final soulProvider = FutureProvider<Soul>((ref) async {
  final cache = ref.read(sessionCacheProvider);
  if (cache.soul.isNotEmpty) {
    return Soul(personality: cache.soul['personality'] as String? ?? '');
  }
  return ref.read(settingsRepositoryProvider).getSoul();
});
