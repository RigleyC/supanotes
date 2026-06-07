import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class ContextsState {
  final List<UserContext> contexts;
  final bool isLoading;

  const ContextsState({
    this.contexts = const [],
    this.isLoading = false,
  });

  ContextsState copyWith({
    List<UserContext>? contexts,
    bool? isLoading,
  }) =>
      ContextsState(
        contexts: contexts ?? this.contexts,
        isLoading: isLoading ?? this.isLoading,
      );
}

final contextsControllerProvider =
    AsyncNotifierProvider<ContextsController, ContextsState>(
  ContextsController.new,
);

class ContextsController extends AsyncNotifier<ContextsState> {
  @override
  Future<ContextsState> build() async {
    final contexts = await ref.read(settingsRepositoryProvider).getContexts();
    return ContextsState(contexts: contexts);
  }

  Future<void> loadContexts() async {
    state = AsyncValue.data(ContextsState(isLoading: true));
    final contexts = await ref.read(settingsRepositoryProvider).getContexts();
    state = AsyncValue.data(ContextsState(contexts: contexts));
  }

  Future<void> createContext(String name) async {
    await ref.read(settingsRepositoryProvider).createContext(name);
    await loadContexts();
  }

  Future<void> deleteContext(String id) async {
    await ref.read(settingsRepositoryProvider).deleteContext(id);
    await loadContexts();
  }
}
