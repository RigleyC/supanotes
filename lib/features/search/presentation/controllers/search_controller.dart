import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResultModel>, ({String query, SearchMode mode})>(
  (ref, params) async {
    return ref.read(searchRepositoryProvider).search(
          query: params.query,
          mode: params.mode,
        );
  },
);

class SearchModeNotifier extends Notifier<SearchMode> {
  @override
  SearchMode build() => SearchMode.hybrid;

  void set(SearchMode mode) => state = mode;
}

final searchModeProvider =
    NotifierProvider.autoDispose<SearchModeNotifier, SearchMode>(
  SearchModeNotifier.new,
);
