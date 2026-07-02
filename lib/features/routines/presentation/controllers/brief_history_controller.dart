import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/routines/data/routines_repository.dart';
import 'package:supanotes/features/routines/domain/routine_log_model.dart';

final briefHistoryProvider = FutureProvider.autoDispose<List<RoutineLogModel>>((
  ref,
) async {
  ref.watch(sessionResetProvider);
  return ref.read(routinesRepositoryProvider).getLogs();
});
