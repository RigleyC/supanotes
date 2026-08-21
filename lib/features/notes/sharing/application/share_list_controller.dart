import 'package:riverpod/src/providers/future_provider.dart';

import 'package:supanotes/features/notes/sharing/data/shares_repository.dart';
import 'package:supanotes/features/notes/sharing/model/share_model.dart';

final FutureProviderFamily<List<ShareModel>, String> shareListProvider = FutureProvider.autoDispose
    .family<List<ShareModel>, String>((ref, noteId) {
      return ref.read(sharesRepositoryProvider).listShares(noteId: noteId);
    });
