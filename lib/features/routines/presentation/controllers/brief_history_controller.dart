import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/routines/data/routines_repository.dart';
import 'package:supanotes/features/routines/domain/routine_log_model.dart';

class BriefHistoryState {
  final List<RoutineLogModel> logs;
  final bool isLoading;

  const BriefHistoryState({
    this.logs = const [],
    this.isLoading = false,
  });

  BriefHistoryState copyWith({
    List<RoutineLogModel>? logs,
    bool? isLoading,
  }) =>
      BriefHistoryState(
        logs: logs ?? this.logs,
        isLoading: isLoading ?? this.isLoading,
      );
}

final briefHistoryControllerProvider =
    AsyncNotifierProvider<BriefHistoryController, BriefHistoryState>(
  BriefHistoryController.new,
);

class BriefHistoryController extends AsyncNotifier<BriefHistoryState> {
  @override
  Future<BriefHistoryState> build() async {
    final logs = await ref.read(routinesRepositoryProvider).getLogs();
    return BriefHistoryState(logs: logs);
  }

  Future<void> loadLogs() async {
    state = AsyncValue.data(BriefHistoryState(isLoading: true));
    final logs = await ref.read(routinesRepositoryProvider).getLogs();
    state = AsyncValue.data(BriefHistoryState(logs: logs));
  }

  Future<void> refresh() async {
    await loadLogs();
  }
}
