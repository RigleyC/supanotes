import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/shares_repository.dart';
import '../../domain/share_permission.dart';

final shareNoteControllerProvider = StateNotifierProvider.autoDispose
    .family<ShareNoteController, AsyncValue<void>, String>((ref, noteId) {
      return ShareNoteController(
        noteId: noteId,
        repository: ref.read(sharesRepositoryProvider),
      );
    });

class ShareNoteController extends StateNotifier<AsyncValue<void>> {
  ShareNoteController({
    required String noteId,
    required SharesRepository repository,
  }) : _noteId = noteId,
       _repository = repository,
       super(const AsyncValue.data(null));

  final String _noteId;
  final SharesRepository _repository;
  int _nextOperation = 0;

  Future<void> share({
    required String email,
    required SharePermission permission,
  }) async {
    final operationId = ++_nextOperation;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _repository.shareNote(
        noteId: _noteId,
        email: email,
        permission: permission,
      ),
    );
    if (operationId == _nextOperation) {
      state = result;
    }
  }

  Future<void> revoke({required String userId}) async {
    final operationId = ++_nextOperation;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _repository.deleteShare(noteId: _noteId, userId: userId),
    );
    if (operationId == _nextOperation) {
      state = result;
    }
  }
}
