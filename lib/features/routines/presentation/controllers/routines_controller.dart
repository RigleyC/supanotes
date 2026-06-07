import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/routines/data/routines_repository.dart';
import 'package:supanotes/features/routines/domain/routine_model.dart';

class RoutinesState {
  final List<RoutineModel> routines;
  final bool isLoading;

  const RoutinesState({
    this.routines = const [],
    this.isLoading = false,
  });

  RoutinesState copyWith({
    List<RoutineModel>? routines,
    bool? isLoading,
  }) =>
      RoutinesState(
        routines: routines ?? this.routines,
        isLoading: isLoading ?? this.isLoading,
      );
}

final routinesControllerProvider =
    AsyncNotifierProvider<RoutinesController, RoutinesState>(
  RoutinesController.new,
);

class RoutinesController extends AsyncNotifier<RoutinesState> {
  @override
  Future<RoutinesState> build() async {
    final routines = await ref.read(routinesRepositoryProvider).getRoutines();
    return RoutinesState(routines: routines);
  }

  Future<void> loadRoutines() async {
    state = const AsyncValue.data(RoutinesState(isLoading: true));
    final routines = await ref.read(routinesRepositoryProvider).getRoutines();
    state = AsyncValue.data(RoutinesState(routines: routines));
  }

  Future<void> refresh() async {
    await loadRoutines();
  }
}
