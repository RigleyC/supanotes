import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/memories/data/memories_repository.dart';
import 'package:supanotes/features/memories/domain/memory_model.dart';

final memoriesControllerProvider =
    AsyncNotifierProvider.autoDispose<MemoriesController, List<MemoryModel>>(
      MemoriesController.new,
    );

class MemoriesController extends AsyncNotifier<List<MemoryModel>> {
  @override
  Future<List<MemoryModel>> build() {
    ref.watch(sessionResetProvider);
    return _loadMemories();
  }

  Future<List<MemoryModel>> _loadMemories() async {
    final memories = await ref.read(memoriesRepositoryProvider).getMemories();
    return memories;
  }

  Future<void> createMemory({
    required String content,
    String? contextSlug,
  }) async {
    try {
      await ref
          .read(memoriesRepositoryProvider)
          .createMemory(content: content, contextSlug: contextSlug);
      state = AsyncValue.data(await _loadMemories());
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteMemory(String id) async {
    try {
      await ref.read(memoriesRepositoryProvider).deleteMemory(id);
      state = AsyncValue.data(await _loadMemories());
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
