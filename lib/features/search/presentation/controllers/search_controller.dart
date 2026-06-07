import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

class SearchState {
  final String query;
  final SearchMode mode;
  final List<SearchResultModel> results;
  final bool isLoading;
  final String? error;

  const SearchState({
    this.query = '',
    this.mode = SearchMode.hybrid,
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  SearchState copyWith({
    String? query,
    SearchMode? mode,
    List<SearchResultModel>? results,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        mode: mode ?? this.mode,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

final searchControllerProvider =
    AsyncNotifierProvider<SearchController, SearchState>(
  SearchController.new,
);

class SearchController extends AsyncNotifier<SearchState> {
  @override
  Future<SearchState> build() async {
    return const SearchState();
  }

  Future<void> search(String query) async {
    state = AsyncValue.data(
      state.value!.copyWith(query: query, isLoading: true),
    );
    try {
      final repo = ref.read(searchRepositoryProvider);
      final results = await repo.search(query: query, mode: state.value!.mode);
      state = AsyncValue.data(
        state.value!.copyWith(results: results, isLoading: false),
      );
    } catch (e) {
      state = AsyncValue.data(
        state.value!.copyWith(isLoading: false, error: e.toString()),
      );
    }
  }

  void setMode(SearchMode mode) {
    state = AsyncValue.data(state.value!.copyWith(mode: mode));
  }

  void clear() {
    state = AsyncValue.data(
      const SearchState(),
    );
  }
}
