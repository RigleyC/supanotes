import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/routines_repository.dart';
import '../../domain/routine_model.dart';

final dailyBriefProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    return await ref.read(routinesRepositoryProvider).getLatestBrief(
          BriefType.daily,
        );
  } on NotFoundException {
    return null;
  }
});
