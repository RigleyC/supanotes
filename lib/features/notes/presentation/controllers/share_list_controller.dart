import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shares_repository.dart';
import '../../domain/share_model.dart';

final shareListProvider = FutureProvider.autoDispose
    .family<List<ShareModel>, String>((ref, noteId) {
      return ref.read(sharesRepositoryProvider).listShares(noteId: noteId);
    });
