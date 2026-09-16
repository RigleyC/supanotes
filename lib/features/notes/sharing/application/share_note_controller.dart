import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/notes/sharing/data/shares_repository.dart';
import 'package:supanotes/features/notes/sharing/model/share_permission.dart';

final shareNoteControllerProvider = NotifierProvider.autoDispose
    .family<ShareNoteController, AsyncValue<void>, String>(
      ShareNoteController.new,
    );

class ShareNoteController extends Notifier<AsyncValue<void>> {
  ShareNoteController(this._noteId);

  final String _noteId;
  late SharesRepository _repository;
  int _nextOperation = 0;

  @override
  AsyncValue<void> build() {
    _repository = ref.read(sharesRepositoryProvider);
    return const AsyncValue.data(null);
  }

  Future<bool> share({
    required String email,
    required SharePermission permission,
  }) {
    return _runMutation(
      () => _repository.shareNote(
        noteId: _noteId,
        email: email,
        permission: permission,
      ),
    );
  }

  Future<bool> revoke({required String userId}) {
    return _runMutation(
      () => _repository.deleteShare(noteId: _noteId, userId: userId),
    );
  }

  Future<bool> _runMutation(Future<void> Function() mutation) async {
    final operationId = ++_nextOperation;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(mutation);
    if (operationId != _nextOperation) return false;
    state = result;
    return result.hasValue;
  }
}
