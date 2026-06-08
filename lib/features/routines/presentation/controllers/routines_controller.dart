import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/routines/data/routines_repository.dart';
import 'package:supanotes/features/routines/domain/routine_model.dart';

final routinesProvider = FutureProvider<List<RoutineModel>>((ref) async {
  final cache = ref.read(sessionCacheProvider);
  if (cache.routines.isNotEmpty) {
    return cache.routines
        .map((raw) => RoutineModel.fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
  }
  return ref.read(routinesRepositoryProvider).getRoutines();
});
