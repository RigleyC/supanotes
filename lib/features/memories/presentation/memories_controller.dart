import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/memories/data/memories_repository.dart';
import 'package:supanotes/features/memories/domain/memory_model.dart';

typedef MemoriesState = ({
  List<MemoryModel> memories,
  bool isLoading,
  String? error,
});

final memoriesControllerProvider =
    NotifierProvider<MemoriesController, MemoriesState>(
  MemoriesController.new,
);

class MemoriesController extends Notifier<MemoriesState> {
  @override
  MemoriesState build() {
    Future.microtask(_loadMemories);
    return (memories: const [], isLoading: true, error: null);
  }

  Future<void> _loadMemories() async {
    state = (memories: state.memories, isLoading: true, error: null);
    try {
      final memories =
          await ref.read(memoriesRepositoryProvider).getMemories();
      state = (memories: memories, isLoading: false, error: null);
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }

  Future<void> createMemory({required String content, String? contextSlug}) async {
    try {
      await ref.read(memoriesRepositoryProvider).createMemory(
            content: content,
            contextSlug: contextSlug,
          );
      await _loadMemories();
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }

  Future<void> deleteMemory(String id) async {
    try {
      await ref.read(memoriesRepositoryProvider).deleteMemory(id);
      await _loadMemories();
    } on ApiException catch (e) {
      state = (memories: state.memories, isLoading: false, error: e.message);
    }
  }
}
