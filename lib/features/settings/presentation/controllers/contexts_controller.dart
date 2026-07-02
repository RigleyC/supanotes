import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

final contextsProvider = FutureProvider.autoDispose<List<UserContext>>((
  ref,
) async {
  ref.watch(sessionResetProvider);
  final cache = ref.read(sessionCacheProvider);
  if (cache.contexts.isNotEmpty) {
    return cache.contexts
        .map((raw) => UserContext.fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
  }
  return ref.read(settingsRepositoryProvider).getContexts();
});
