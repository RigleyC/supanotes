import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResultModel>, String>((ref, query) async {
      return ref.read(searchRepositoryProvider).search(query: query);
    });
