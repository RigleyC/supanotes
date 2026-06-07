import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

class InboxState {
  final NoteModel? inboxNote;
  final bool isSaving;
  final bool hasContent;

  const InboxState({
    this.inboxNote,
    this.isSaving = false,
    this.hasContent = false,
  });

  InboxState copyWith({
    NoteModel? inboxNote,
    bool? isSaving,
    bool? hasContent,
  }) =>
      InboxState(
        inboxNote: inboxNote ?? this.inboxNote,
        isSaving: isSaving ?? this.isSaving,
        hasContent: hasContent ?? this.hasContent,
      );
}

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(
  InboxController.new,
);

class InboxController extends AsyncNotifier<InboxState> {
  @override
  Future<InboxState> build() async {
    final inbox = await ref.read(notesRepositoryProvider).watchInbox().first;
    return InboxState(
      inboxNote: inbox,
      hasContent: (inbox?.content.length ?? 0) > 0,
    );
  }

  Future<void> loadOrCreateInbox() async {
    final repo = ref.read(notesRepositoryProvider);
    final inbox = await repo.watchInbox().first;
    state = AsyncValue.data(
      InboxState(
        inboxNote: inbox,
        hasContent: (inbox?.content.length ?? 0) > 0,
      ),
    );
  }

  Future<void> autoSave() async {
    // Will be implemented when inbox_screen is refactored
  }

  Future<void> syncTasks() async {
    // Will be implemented when inbox_screen is refactored
  }
}
